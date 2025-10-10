import pytest
from django.utils import timezone
from decimal import Decimal
from bank_accounts.models import BankAccount, BankTransaction, BankAudit


@pytest.mark.django_db
def test_bank_account_set_iban_and_save(active_user):
    profile = active_user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="BNI")

    # Définir un IBAN
    iban = "FR76 3000 6000 0112 3456 7890 189"
    account.set_iban(iban)
    account.save()

    account.refresh_from_db()
    assert account.iban_normalized == "FR7630006000011234567890189"
    assert account.masked_account.startswith("FR76")
    assert "*" in account.masked_account
    assert account.iban_encrypted == iban  # EncryptedTextField restitue le plaintext


@pytest.mark.django_db
def test_bank_account_str(active_user):
    profile = active_user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="BOA")
    account.set_iban("MG4600000000000000000000000")
    account.save()

    s = str(account)
    assert profile.id.hex[:6] in s or profile.username in s or "profile" in s
    assert account.masked_account in s


@pytest.mark.django_db
def test_bank_transaction_creation_and_str(active_user):
    profile = active_user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="BFV")
    tx = BankTransaction.objects.create(
        bank_account=account,
        profile=profile,
        type="credit",
        amount=Decimal("1000.50"),
        currency="MGA",
        description="Salaire",
    )
    assert "credit" in str(tx)
    assert "1000.50" in str(tx)
    assert "MGA" in str(tx)


@pytest.mark.django_db
def test_bank_audit_creation_and_str(active_user):
    audit = BankAudit.objects.create(
        actor=active_user,
        action="bank_account.create",
        target_type="BankAccount",
        target_id="12345",
        detail={"info": "test"},
    )
    s = str(audit)
    assert "bank_account.create" in s
    assert "BankAccount:12345" in s
    assert str(active_user.id) in s