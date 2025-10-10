import pytest
from rest_framework.test import APIRequestFactory
from bank_accounts.serializers import (
    BankAccountCreateSerializer,
    BankAccountUpdateSerializer,
    BankAccountDetailSerializer,
    BankTransactionSerializer,
)
from bank_accounts.models import BankAccount, BankTransaction
from activities.models import Activity
from decimal import Decimal
from manage_personnel.models import Profile


@pytest.mark.django_db
def test_create_serializer_requires_iban_or_account_number(active_user):
    profile = active_user.profile
    data = {"profile": profile.id, "bank_name": "BNI"}
    serializer = BankAccountCreateSerializer(data=data)
    assert not serializer.is_valid()
    assert "Either iban or account_number must be provided." in str(serializer.errors)


@pytest.mark.django_db
def test_create_serializer_with_iban(active_user):
    profile = active_user.profile
    data = {"profile": profile.id, "iban": "FR7630006000011234567890189"}
    serializer = BankAccountCreateSerializer(data=data)
    assert serializer.is_valid(), serializer.errors
    account = serializer.save()
    assert account.iban_normalized == "FR7630006000011234567890189"
    assert "*" in account.masked_account


@pytest.mark.django_db
def test_create_serializer_with_account_number(active_user):
    profile = active_user.profile
    data = {"profile": profile.id, "account_number": "1234567890"}
    serializer = BankAccountCreateSerializer(data=data)
    assert serializer.is_valid(), serializer.errors
    account = serializer.save()
    assert account.account_number_encrypted == "1234567890"
    assert account.masked_account is not None


@pytest.mark.django_db
def test_create_serializer_sets_primary(active_user, django_user_model):
    # Premier compte primaire sur le profil existant
    profile1 = active_user.profile
    acc1 = BankAccount.objects.create(profile=profile1, bank_name="BNI", is_primary=True)

    # Deuxième utilisateur + profil
    user2 = django_user_model.objects.create_user(username="u2", email="u2@test.com", password="pwd")
    profile2 = getattr(user2, "profile", None)
    if profile2 is None:
        profile2 = Profile.objects.create(user=user2)

    data = {"profile": profile2.id, "account_number": "1111", "is_primary": True}
    serializer = BankAccountCreateSerializer(data=data)
    assert serializer.is_valid(), serializer.errors
    acc2 = serializer.save()

    # Chaque profil a son compte primaire
    assert acc1.is_primary is True
    assert acc2.is_primary is True


@pytest.mark.django_db
def test_update_serializer_accepts_fields(active_user):
    profile = active_user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="Old")
    data = {"bank_name": "New"}
    serializer = BankAccountUpdateSerializer(account, data=data, partial=True)
    assert serializer.is_valid(), serializer.errors
    updated = serializer.save()
    assert updated.bank_name == "New"


@pytest.mark.django_db
def test_detail_serializer_owner_and_non_owner(active_user, django_user_model):
    profile = active_user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="BNI")
    account.set_iban("FR7630006000011234567890189")
    account.account_number_encrypted = "1234567890"  
    account.save()

    factory = APIRequestFactory()

    # Owner → doit voir les champs sensibles
    request = factory.get("/")
    request.user = active_user
    serializer = BankAccountDetailSerializer(account, context={"request": request})
    data = serializer.data
    assert data["iban"] is not None
    assert data["account_number"] is not None  

    # Non-owner → ne doit pas voir les champs sensibles
    other_user = django_user_model.objects.create_user(username="other", email="other@test.com", password="pwd")
    request2 = factory.get("/")
    request2.user = other_user
    serializer2 = BankAccountDetailSerializer(account, context={"request": request2})
    data2 = serializer2.data
    assert data2["iban"] is None
    assert data2["account_number"] is None


@pytest.mark.django_db
def test_transaction_serializer(active_user):
    profile = active_user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="BNI")
    tx = BankTransaction.objects.create(
        bank_account=account,
        profile=profile,
        type="credit",
        amount=Decimal("100.00"),
    )
    serializer = BankTransactionSerializer(tx)
    data = serializer.data
    assert data["amount"] == "100.00"
    assert "id" in data
    assert "created_at" in data


# ---------------- SIGNALS ----------------

@pytest.mark.django_db
def test_post_save_creates_activity(active_user):
    profile = active_user.profile
    Activity.objects.all().delete()
    account = BankAccount.objects.create(profile=profile, bank_name="BNI")
    act = Activity.objects.filter(external_id=f"bank_account:{account.id}").last()
    assert act is not None
    assert act.meta["action"] == "create"


@pytest.mark.django_db
def test_post_save_update_creates_activity_with_diff(active_user):
    profile = active_user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="BNI")
    Activity.objects.all().delete()  # reset
    account.bank_name = "BOA"
    account.save()
    act = Activity.objects.filter(external_id=f"bank_account:{account.id}").last()
    assert act is not None
    assert "bank_name" in act.meta["diff"]


@pytest.mark.django_db
def test_post_delete_creates_activity(active_user):
    profile = active_user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="BNI")
    account_id = account.id
    Activity.objects.all().delete()  # reset avant suppression
    account.delete()
    act = Activity.objects.filter(external_id=f"bank_account:{account_id}").last()
    assert act is not None
    assert act.meta["action"] == "delete"
    assert act.visible is False