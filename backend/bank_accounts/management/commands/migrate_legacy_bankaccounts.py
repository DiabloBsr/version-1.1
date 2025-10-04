from typing import Optional, Iterable, Tuple
import importlib
import json
import logging

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.contrib.auth import get_user_model

from bank_accounts.models import BankAccount as NewBankAccount
from manage_personnel.models import Profile

logger = logging.getLogger(__name__)
User = get_user_model()


def _resolve_legacy_model(candidate_paths: Tuple[str, ...]) -> Optional[type]:
    """
    Try multiple import paths and return the legacy model class or None.
    Candidates may be:
      - "app.module:ClassName"
      - "app.module.ClassName"
    """
    for path in candidate_paths:
        if not path:
            continue
        try:
            if ":" in path:
                module_path, cls_name = path.split(":", 1)
            else:
                *module_parts, cls_name = path.split(".")
                module_path = ".".join(module_parts)
            module = importlib.import_module(module_path)
            legacy = getattr(module, cls_name, None)
            if legacy is not None:
                logger.info("Found legacy model %s in %s", cls_name, module_path)
                return legacy
        except ImportError:
            logger.debug("ImportError while trying to import candidate %s", path)
        except Exception:
            logger.exception("Unexpected error while resolving legacy model for candidate %s", path)
    return None


# Default candidates to attempt; edit to include your project's legacy locations
_DEFAULT_LEGACY_CANDIDATES = (
    "legacy_app.models:BankAccount",
    "legacy_app.models.BankAccount",
    "legacy_qa.models:DarkAccount",
    "legacy_qa.models.DarkAccount",
    "old_banking.models:Account",
    "old_banking.models.Account",
)


class Command(BaseCommand):
    help = (
        "Migrate legacy bank accounts into bank_accounts.BankAccount. "
        "Default is dry-run. Use --commit to persist changes."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--commit",
            action="store_true",
            help="Persist changes to the database. Without this flag the command runs a dry-run.",
        )
        parser.add_argument(
            "--batch-size",
            type=int,
            default=200,
            help="Number of legacy rows to process per iteration (default: 200).",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=0,
            help="Optional limit to the total number of legacy rows to evaluate (0 = no limit).",
        )
        parser.add_argument(
            "--fail-fast",
            action="store_true",
            help="Abort on first unexpected error.",
        )
        parser.add_argument(
            "--legacy-app",
            type=str,
            default="",
            help=(
                "Comma-separated candidate import paths for the legacy model(s). "
                "Examples: 'manage_personnel.legacy_models:BankAccount' or "
                "'legacy_app.models.BankAccount,legacy_qa.models:DarkAccount'."
            ),
        )

    def handle(self, *args, **options):
        # Resolve legacy model candidates from CLI option first, then defaults
        legacy_option = options.get("legacy_app", "") or ""
        candidates = tuple(s.strip() for s in legacy_option.split(",") if s.strip()) if legacy_option else ()
        if not candidates:
            candidates = _DEFAULT_LEGACY_CANDIDATES

        LegacyBankAccount = _resolve_legacy_model(candidates)
        if LegacyBankAccount is None:
            msg = (
                "LegacyBankAccount model not importable. Provide correct --legacy-app candidates "
                "or edit _DEFAULT_LEGACY_CANDIDATES in this command."
            )
            self.stderr.write(msg)
            logger.error(msg)
            raise CommandError(msg)

        commit: bool = options["commit"]
        batch_size: int = options["batch_size"]
        limit: int = options["limit"]
        fail_fast: bool = options["fail_fast"]

        qs = LegacyBankAccount.objects.all().order_by("id")
        total = qs.count()
        if limit and limit > 0:
            total = min(total, limit)
            qs = qs[:limit]

        self.stdout.write(f"Found {total} legacy bank accounts to evaluate (commit={commit}).")

        migrated = 0
        skipped = 0
        errors = 0

        # iterate in chunks
        def iter_chunks(queryset: Iterable, size: int):
            start = 0
            while True:
                chunk = list(queryset[start : start + size])
                if not chunk:
                    break
                yield chunk
                start += size

        try:
            for chunk in iter_chunks(qs, batch_size):
                for la in chunk:
                    legacy_id = getattr(la, "id", None) or getattr(la, "pk", None)
                    try:
                        # Resolve target profile
                        profile: Optional[Profile] = None

                        # Common legacy link patterns; adapt if your legacy model differs
                        if getattr(la, "profile_id", None):
                            profile = Profile.objects.filter(pk=la.profile_id).first()
                        elif getattr(la, "profile", None) and getattr(la.profile, "id", None):
                            profile = Profile.objects.filter(pk=la.profile.id).first()
                        elif getattr(la, "user_id", None):
                            profile = Profile.objects.filter(user_id=la.user_id).first()
                        elif getattr(la, "email", None):
                            profile = Profile.objects.filter(user__email=getattr(la, "email")).first()

                        if profile is None:
                            skipped += 1
                            self.stdout.write(f"Skipping legacy id={legacy_id}: no matching Profile found.")
                            continue

                        # Try to pick IBAN or account number from likely fields on legacy model
                        iban_raw = getattr(la, "iban", None) or getattr(la, "raw_iban", None)
                        acct_raw = getattr(la, "account_number", None) or getattr(la, "raw_account_number", None)

                        # Create or update logic: attempt to find an existing migrated record by a migration marker
                        migrated_from_meta = getattr(la, "migrated_to_bank_id", None) or getattr(la, "migrated_to", None)

                        if not commit:
                            # dry-run: output what would be done
                            self.stdout.write(
                                f"[DRY] legacy id={legacy_id} -> profile={profile.id} iban={bool(iban_raw)} acct={bool(acct_raw)}"
                            )
                            migrated += 1
                            continue

                        # commit mode: create the new BankAccount
                        with transaction.atomic():
                            nb = NewBankAccount(
                                profile=profile,
                                label=getattr(la, "label", "Compte"),
                                bank_name=getattr(la, "bank_name", "") or getattr(la, "bank", ""),
                                bank_code=getattr(la, "bank_code", "") or getattr(la, "bank_code", ""),
                                agency=getattr(la, "agency", "") or getattr(la, "branch", ""),
                                currency=getattr(la, "currency", "XOF") or getattr(la, "curr", "XOF"),
                                status=getattr(la, "status", "pending"),
                                is_primary=bool(getattr(la, "is_primary", False)),
                            )

                            # Prefer IBAN if present so normalization and masked_account helpers run
                            if iban_raw:
                                try:
                                    nb.set_iban(str(iban_raw))
                                except Exception as e_setiban:
                                    # fallback to direct encrypted field write if helper fails
                                    nb.iban_encrypted = str(iban_raw)
                                    nb.masked_account = nb._mask_iban(str(iban_raw))
                                    logger.warning(f"set_iban failed for legacy id={legacy_id}: {e_setiban}")
                            elif acct_raw:
                                # store account number into account_number_encrypted and produce a masked_account
                                nb.account_number_encrypted = str(acct_raw)
                                nb.masked_account = nb._mask_iban(str(acct_raw))

                            nb.save()

                            # Optional: mark legacy row as migrated if legacy schema supports it
                            try:
                                if hasattr(la, "migrated_to_bank_id"):
                                    setattr(la, "migrated_to_bank_id", nb.id)
                                    la.save(update_fields=["migrated_to_bank_id"])
                            except Exception:
                                # non-critical
                                logger.debug("Could not mark legacy row as migrated (field missing or write failed)")

                            self.stdout.write(f"Migrated legacy id={legacy_id} -> new id={nb.id}")
                            migrated += 1

                    except Exception as e:
                        errors += 1
                        self.stderr.write(f"Error migrating legacy id={legacy_id}: {e}")
                        logger.exception("migration error for legacy id=%s", legacy_id)
                        if fail_fast:
                            raise

        except Exception as e_outer:
            # catch any unexpected higher-level errors
            self.stderr.write(f"Migration aborted: {e_outer}")
            logger.exception("Migration aborted unexpectedly")
            raise CommandError("Migration aborted due to unexpected error") from e_outer

        # Summary
        self.stdout.write(
            f"Done. processed={migrated + skipped + errors} migrated={migrated} skipped={skipped} errors={errors} (commit={commit})"
        )
        if errors:
            self.stderr.write("One or more errors occurred during migration; check the logs for details.")