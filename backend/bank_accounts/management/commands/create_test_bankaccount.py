from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from manage_personnel.models import Profile
from bank_accounts.mo

class Command(BaseCommand):
    help = "Create a test BankAccount for the first Profile (useful to validate encryption and API)."

    def add_arguments(self, parser):
        parser.add_argument("--label", type=str, default="Compte test", help="Label for the test account")
        parser.add_argument("--bank-name", dest="bank_name", type=str, default="TestBank", help="Bank name")
        parser.add_argument("--account-number", dest="account_number", type=str, default="FR7612345678901234567890123", help="Account/IBAN to store (plaintext for test)")
        parser.add_argument("--profile-id", dest="profile_id", type=int, default=0, help="Profile id to attach to (0 = first profile)")

    def handle(self, *args, **options):
        label = options["label"]
        bank_name = options["bank_name"]
        account_number = options["account_number"]
        profile_id = options["profile_id"]

        if profile_id:
            profile = Profile.objects.filter(pk=profile_id).first()
        else:
            profile = Profile.objects.first()

        if not profile:
            raise CommandError("No Profile found. Create a Profile in admin first.")

        with transaction.atomic():
            nb = BankAccount(profile=profile, label=label, bank_name=bank_name)
            # assign plaintext; EncryptedTextField should encrypt on save
            nb.account_number_encrypted = account_number
            try:
                nb.masked_account = nb._mask_iban(account_number)
            except Exception:
                nb.masked_account = (account_number[:4] + "..." ) if account_number else ""
            nb.save()
        self.stdout.write(f"Created test BankAccount id={nb.id} profile={profile.id} masked={nb.masked_account}")