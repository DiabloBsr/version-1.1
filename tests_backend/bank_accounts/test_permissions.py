import pytest
from django.contrib.auth import get_user_model
from rest_framework.test import APIRequestFactory
from bank_accounts.permissions import IsProfileOwnerOrStaff
from manage_personnel.models import Profile


User = get_user_model()


class DummyProfile:
    def __init__(self, user=None, user_id=None):
        self.user = user
        self.user_id = user_id


class DummyObj:
    def __init__(self, profile):
        self.profile = profile


@pytest.mark.django_db
def test_staff_user_always_allowed():
    staff = User.objects.create_user(username="staff", email="staff@test.com", password="pwd", is_staff=True)
    profile = DummyProfile(user=None)
    obj = DummyObj(profile)

    factory = APIRequestFactory()
    request = factory.get("/")
    request.user = staff

    perm = IsProfileOwnerOrStaff()
    assert perm.has_object_permission(request, None, obj) is True


@pytest.mark.django_db
def test_owner_allowed_via_profile_user():
    user = User.objects.create_user(username="owner", email="owner@test.com", password="pwd")
    profile = DummyProfile(user=user)
    obj = DummyObj(profile)

    factory = APIRequestFactory()
    request = factory.get("/")
    request.user = user

    perm = IsProfileOwnerOrStaff()
    assert perm.has_object_permission(request, None, obj) is True


@pytest.mark.django_db
def test_owner_allowed_via_profile_user_id():
    user = User.objects.create_user(username="owner2", email="owner2@test.com", password="pwd")
    profile = DummyProfile(user_id=user.id)
    obj = DummyObj(profile)

    factory = APIRequestFactory()
    request = factory.get("/")
    request.user = user

    perm = IsProfileOwnerOrStaff()
    assert perm.has_object_permission(request, None, obj) is True


@pytest.mark.django_db
def test_non_owner_denied():
    user1 = User.objects.create_user(username="u1", email="u1@test.com", password="pwd")
    user2 = User.objects.create_user(username="u2", email="u2@test.com", password="pwd")
    profile = DummyProfile(user=user1)
    obj = DummyObj(profile)

    factory = APIRequestFactory()
    request = factory.get("/")
    request.user = user2

    perm = IsProfileOwnerOrStaff()
    assert perm.has_object_permission(request, None, obj) is False



@pytest.mark.django_db
def test_direct_profile_object(active_user):
    profile = active_user.profile  # ✅ réutiliser le profil existant
    factory = APIRequestFactory()
    request = factory.get("/")
    request.user = active_user

    perm = IsProfileOwnerOrStaff()
    assert perm.has_object_permission(request, None, profile) is True