import pytest
from django.contrib.auth import get_user_model
from backend.accounts.serializers import RegisterSerializer, TOTPVerifySerializer

User = get_user_model()


@pytest.mark.django_db
def test_register_serializer_creates_user():
    data = {
        "email": "newuser@example.com",
        "password": "strongpassword",
        "first_name": "John",
        "last_name": "Doe",
        "username": "newuser",  # username requis
    }
    serializer = RegisterSerializer(data=data)
    assert serializer.is_valid(), serializer.errors
    user = serializer.save()
    assert user.email == "newuser@example.com"
    assert user.check_password("strongpassword")


@pytest.mark.django_db
def test_register_serializer_rejects_duplicate_email():
    User.objects.create_user(
        email="dup@example.com",
        password="pass12345",
        username="dup"  # username requis
    )
    data = {
        "email": "dup@example.com",
        "password": "anotherpass",
        "first_name": "Jane",
        "last_name": "Smith",
        "username": "dup2",  # username requis
    }
    serializer = RegisterSerializer(data=data)
    assert not serializer.is_valid()
    assert "email" in serializer.errors


def test_totp_verify_serializer_requires_otp():
    serializer = TOTPVerifySerializer(data={})
    assert not serializer.is_valid()
    assert "otp" in serializer.errors