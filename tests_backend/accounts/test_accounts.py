import pytest
import pyotp
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

User = get_user_model()


@pytest.mark.django_db
def test_register_view_creates_user():
    client = APIClient()
    payload = {
        "email": "register@example.com",
        "password": "password123",
        "first_name": "Alice",
        "last_name": "Wonder",
        "username": "registeruser",  # username requis
    }
    response = client.post("/api/v1/auth/register/", payload, format="json")
    assert response.status_code == 201
    assert User.objects.filter(email="register@example.com").exists()


@pytest.mark.django_db
def test_logout_view_with_valid_token(active_user):
    client = APIClient()
    refresh = RefreshToken.for_user(active_user)
    client.force_authenticate(user=active_user)
    response = client.post("/api/v1/auth/logout/", {"refresh": str(refresh)}, format="json")
    assert response.status_code == 205
    assert response.data["success"] is True
    assert response.data["detail"] == "logout successful"


@pytest.mark.django_db
def test_logout_view_without_token(active_user):
    client = APIClient()
    client.force_authenticate(user=active_user)
    response = client.post("/api/v1/auth/logout/", {}, format="json")
    assert response.status_code == 400
    assert response.data["success"] is False
    assert "refresh token required" in response.data["detail"]


@pytest.mark.django_db
def test_logout_view_invalid_token(active_user):
    client = APIClient()
    client.force_authenticate(user=active_user)
    response = client.post("/api/v1/auth/logout/", {"refresh": "badtoken"}, format="json")
    assert response.status_code == 400
    assert response.data["success"] is False
    assert "invalid token" in response.data["detail"]


@pytest.mark.django_db
def test_password_reset_request_requires_email():
    client = APIClient()
    response = client.post("/api/v1/auth/password_reset/", {}, format="json")
    assert response.status_code == 400
    assert "email required" in response.data["detail"]


@pytest.mark.django_db
def test_password_reset_request_with_email(active_user):
    client = APIClient()
    response = client.post("/api/v1/auth/password_reset/", {"email": active_user.email}, format="json")
    assert response.status_code == 200
    assert response.data["success"] is True
    assert "reset link" in response.data["detail"].lower()


@pytest.mark.django_db
def test_totp_setup_and_verify(active_user):
    client = APIClient()
    client.force_authenticate(user=active_user)

    # Setup MFA (POST)
    response = client.post("/api/v1/auth/mfa/setup/")
    assert response.status_code == 200
    assert response.data["success"] is True
    assert response.data["detail"] == "MFA setup complete"
    assert response.data["qr_base64"].startswith("data:image/png;base64,")

    # Verify MFA
    secret = User.objects.get(id=active_user.id).totp_secret
    totp = pyotp.TOTP(secret)
    otp = totp.now()
    response = client.post("/api/v1/auth/mfa/verify/", {"otp": otp}, format="json")
    assert response.status_code == 200
    assert response.data["success"] is True
    assert response.data["detail"] == "verified"


@pytest.mark.django_db
def test_totp_verify_without_setup(active_user):
    client = APIClient()
    client.force_authenticate(user=active_user)
    response = client.post("/api/v1/auth/mfa/verify/", {"otp": "123456"}, format="json")
    assert response.status_code == 400
    assert response.data["detail"] == "MFA not setup"


@pytest.mark.django_db
def test_totp_verify_invalid_otp(active_user):
    client = APIClient()
    client.force_authenticate(user=active_user)
    # Setup MFA first
    client.post("/api/v1/auth/mfa/setup/")
    response = client.post("/api/v1/auth/mfa/verify/", {"otp": "000000"}, format="json")
    assert response.status_code == 400
    assert response.data["detail"] == "invalid otp"