import pytest
from rest_framework.test import APIClient
from rest_framework.reverse import reverse
from bank_accounts.models import BankAccount


@pytest.mark.django_db
def test_owner_can_create_and_retrieve_bankaccount(django_user_model):
    user = django_user_model.objects.create_user(username="owner", email="owner@test.com", password="pwd")
    profile = user.profile
    client = APIClient()
    client.force_authenticate(user=user)

    url = reverse("bank_accounts:bankaccount-list")
    data = {
        "profile": profile.id,
        "iban": "FR7630006000011234567890189",
        "bank_name": "BNI",
    }
    resp = client.post(url, data, format="json")
    assert resp.status_code == 201
    account_id = resp.data["id"]

    # Retrieve
    url_detail = reverse("bank_accounts:bankaccount-detail", args=[account_id])
    resp2 = client.get(url_detail)
    assert resp2.status_code == 200
    assert resp2.data["iban"] is not None
    assert resp2.data["masked_account"] is not None


@pytest.mark.django_db
def test_non_owner_cannot_access_other_account(django_user_model):
    user1 = django_user_model.objects.create_user(username="u1", email="u1@test.com", password="pwd")
    profile1 = user1.profile
    account = BankAccount.objects.create(profile=profile1, bank_name="BNI")

    user2 = django_user_model.objects.create_user(username="u2", email="u2@test.com", password="pwd")
    client = APIClient()
    client.force_authenticate(user=user2)

    url_detail = reverse("bank_accounts:bankaccount-detail", args=[account.id])
    resp = client.get(url_detail)
    assert resp.status_code == 404


@pytest.mark.django_db
def test_update_bankaccount(django_user_model):
    user = django_user_model.objects.create_user(username="u1", email="u1@test.com", password="pwd")
    profile = user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="Old")

    client = APIClient()
    client.force_authenticate(user=user)

    url_detail = reverse("bank_accounts:bankaccount-detail", args=[account.id])
    data = {"bank_name": "New"}
    resp = client.patch(url_detail, data, format="json")
    assert resp.status_code == 200
    account.refresh_from_db()
    assert account.bank_name == "New"


@pytest.mark.django_db
def test_destroy_marks_deleted(django_user_model):
    user = django_user_model.objects.create_user(username="u1", email="u1@test.com", password="pwd")
    profile = user.profile
    account = BankAccount.objects.create(profile=profile, bank_name="BNI", is_primary=True)

    client = APIClient()
    client.force_authenticate(user=user)

    url_detail = reverse("bank_accounts:bankaccount-detail", args=[account.id])
    resp = client.delete(url_detail)
    assert resp.status_code == 204

    account.refresh_from_db()
    assert account.status == "deleted"
    assert account.is_primary is False


@pytest.mark.django_db
def test_staff_can_access_all_accounts(django_user_model):
    user1 = django_user_model.objects.create_user(username="u1", email="u1@test.com", password="pwd")
    profile1 = user1.profile
    account = BankAccount.objects.create(profile=profile1, bank_name="BNI")

    staff = django_user_model.objects.create_user(username="staff", email="staff@test.com", password="pwd", is_staff=True)
    client = APIClient()
    client.force_authenticate(user=staff)

    url_detail = reverse("bank_accounts:bankaccount-detail", args=[account.id])
    resp = client.get(url_detail)
    assert resp.status_code == 200
    assert resp.data["id"] == str(account.id)