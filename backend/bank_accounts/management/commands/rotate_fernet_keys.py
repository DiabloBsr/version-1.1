# bank_accounts/management/commands/rotate_fernet_keys.py
import json
import logging
from typing import List, Optional
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.conf import settings

from bank_accounts.models import BankAccount  # uses EncryptedTextField that reads settings.FERNET_KEYS

logger = logging.getLogger(__name__)

class Command(BaseCommand):
    help = "Rotate FERNET_KEYS for EncryptedTextField. Dry-run by default. Use --commit to persist re-encryption."

    def add_arguments(self, parser):
        parser.add_argument("--commit", action="store_true", help="Perform re-encryption; default is dry-run")
        parser.add_argument("--batch-size", type=int, default=200, help="Batch size for processing")
        parser.add_argument("--preview-limit", type=int, default=20, help="Preview N rows in dry-run")

    def handle(self, *args, **options):
        keys = getattr(settings, "FERNET_KEYS", None)
        if not keys or not isinstance(keys, (list, tuple)) or not keys[0]:
            raise CommandError("FERNET_KEYS not configured or invalid in settings")

        commit = options["commit"]
        batch_size = options["batch_size"]
        preview_limit = options["preview_limit"]

        self.stdout.write(f"FERNET_KEYS count={len(keys)} primary will be used for encryption. commit={commit}")

        qs = BankAccount.objects.all().order_by("id")
        total = qs.count()
        self.stdout.write(f"Found {total} BankAccount rows to evaluate")

        if not commit:
            self.stdout.write("Dry-run: showing up to preview_limit entries and whether they decrypt with primary key")
            shown = 0
            for acct in qs[:preview_limit]:
                try:
                    # reading fields goes through EncryptedTextField.to_python/from_db_value
                    iban = acct.iban_encrypted
                    acctnum = acct.account_number_encrypted
                    self.stdout.write(f"[DRY] id={acct.id} iban_present={bool(iban)} acct_present={bool(acctnum)}")
                except Exception as e:
                    self.stderr.write(f"[DRY] id={acct.id} decryption_error: {e}")
                shown += 1
            self.stdout.write("Dry-run complete. To perform rotation run with --commit")
            return

        processed = 0
        errors = 0
        # commit: re-encrypt each record by reading plaintext via current keys and saving (EncryptedTextField will re-encrypt with primary key)
        try:
            for start in range(0, total, batch_size):
                batch = list(qs[start:start+batch_size])
                with transaction.atomic():
                    for acct in batch:
                        try:
                            # Read plaintext values (field class will try all keys for decryption)
                            iban_plain = acct.iban_encrypted
                            acctnum_plain = acct.account_number_encrypted

                            # Force re-save to encrypt with current primary (settings.FERNET_KEYS[0])
                            if iban_plain is not None:
                                acct.iban_encrypted = iban_plain
                            if acctnum_plain is not None:
                                acct.account_number_encrypted = acctnum_plain

                            acct.save(update_fields=["iban_encrypted", "account_number_encrypted"])
                            processed += 1
                        except Exception as e:
                            errors += 1
                            logger.exception("Error re-encrypting BankAccount id=%s", acct.id)
                            if errors > 20:
                                raise
            self.stdout.write(f"Rotation done: processed={processed} errors={errors}")
        except Exception as e:
            raise CommandError(f"Rotation aborted: {e}")