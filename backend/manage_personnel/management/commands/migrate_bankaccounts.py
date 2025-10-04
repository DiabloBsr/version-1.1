# manage_personnel/management/commands/migrate_bankaccounts.py
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

# Apps will be loaded via apps.get_model to be migration-safe
from django.apps import apps


def normalize_iban(value: str) -> str:
    return "".join((value or "").split()).upper()


def mask_iban(value: str) -> str:
    v = "".join((value or "").split())
    if not v:
        return ""
    if len(v) <= 8:
        return v
    # keep first 4 and last 4, mask middle
    return f"{v[:4]}{'*' * (len(v) - 8)}{v[-4:]}"


class Command(BaseCommand):
    help = "Migrate BankAccount rows from manage_personnel to bank_accounts"

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Do not write anything, only report what would be done",
        )
        parser.add_argument(
            "--remove-old",
            action="store_true",
            help="Remove old manage_personnel.BankAccount rows after successful migration",
        )
        parser.add_argument(
            "--batch-size",
            type=int,
            default=200,
            help="Number of rows to process per transaction",
        )

    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        remove_old = options["remove_old"]
        batch = options["batch_size"]

        OldBank = apps.get_model("manage_personnel", "BankAccount")
        NewBank = apps.get_model("bank_accounts", "BankAccount")
        Profile = apps.get_model("manage_personnel", "Profile")

        qs = OldBank.objects.select_related("profile").all().order_by("created_at")
        total = qs.count()
        self.stdout.write(f"Found {total} old BankAccount rows to consider.")

        if total == 0:
            return

        processed = 0
        created = 0
        skipped = 0
        errors = 0

        pk_list = list(qs.values_list("pk", flat=True))

        for start in range(0, len(pk_list), batch):
            chunk = pk_list[start : start + batch]
            old_chunk = OldBank.objects.select_related("profile").filter(pk__in=chunk)

            with transaction.atomic():
                for old in old_chunk:
                    processed += 1
                    try:
                        profile = old.profile
                        if profile is None:
                            skipped += 1
                            self.stdout.write(
                                f"[skip] old id={old.pk} has no profile (skipped)"
                            )
                            continue

                        # Determine raw account value (support account_number or iban fields)
                        raw_account = ""
                        # common field names: account_number, iban, iban_number etc.
                        if hasattr(old, "account_number") and getattr(old, "account_number"):
                            raw_account = getattr(old, "account_number") or ""
                        elif hasattr(old, "iban") and getattr(old, "iban"):
                            raw_account = getattr(old, "iban") or ""
                        else:
                            # fallback try other possible names
                            raw_account = getattr(old, "account_number", "") or ""

                        # Normalize and mask
                        norm = normalize_iban(raw_account)
                        masked = mask_iban(raw_account)

                        # Avoid duplicating: check existing by profile + normalized iban
                        exists = False
                        if norm:
                            exists = NewBank.objects.filter(profile=profile, iban_normalized=norm).exists()
                        else:
                            # if no normalized value, try masked+bank_name heuristics
                            exists = NewBank.objects.filter(profile=profile, masked_account=masked, bank_name=old.bank_name).exists()

                        if exists:
                            skipped += 1
                            self.stdout.write(f"[skip] duplicate for profile={profile.pk}, old id={old.pk}")
                            continue

                        if dry_run:
                            created += 1
                            self.stdout.write(f"[dry-run create] profile={profile.pk} old_id={old.pk} masked={masked} norm={norm}")
                            continue

                        nb = NewBank(
                            profile=profile,
                            label=getattr(old, "bank_name", "") or "Compte",
                            bank_name=getattr(old, "bank_name", "") or "",
                            bank_code=getattr(old, "bank_code", "") or "",
                            agency=getattr(old, "agency", "") or "",
                            is_primary=bool(getattr(old, "is_primary", False)),
                            status="verified",
                            currency=getattr(old, "currency", "XOF") or "XOF",
                            # verification_metadata left null; verified_at now
                            verified_at=timezone.now(),
                        )

                        # set encrypted fields through the model helper or directly
                        # prefer set_iban if provided
                        if hasattr(nb, "set_iban"):
                            nb.set_iban(raw_account)
                        else:
                            nb.iban_encrypted = raw_account
                            nb.iban_normalized = norm
                            nb.masked_account = masked

                        nb.save()
                        created += 1

                        if remove_old:
                            try:
                                # if old model has soft-delete flag, update it; else delete
                                if hasattr(old, "status"):
                                    setattr(old, "status", "removed")
                                    old.save(update_fields=["status"])
                                elif hasattr(old, "is_active"):
                                    setattr(old, "is_active", False)
                                    old.save(update_fields=["is_active"])
                                else:
                                    old.delete()
                            except Exception as e_delete:
                                self.stdout.write(f"[warn] could not remove old id={old.pk}: {e_delete}")

                    except Exception as e:
                        errors += 1
                        self.stderr.write(f"[error] migrating old id={old.pk}: {e}")

        self.stdout.write(f"Processed: {processed}, Created: {created}, Skipped: {skipped}, Errors: {errors}")
        if dry_run:
            self.stdout.write("Dry run completed, no DB writes performed.")
        else:
            self.stdout.write("Migration completed. Verify data before removing old table/model.")