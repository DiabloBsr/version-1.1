import pytest
import pyotp
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

User = get_user_model()

@pytest.mark.django_db
def test_mfa_setup_and_verify():
    # create user
    u = User.objects.create_user(email="mfa@example.com", password="Pass12345", username="mfa")
    assert u is not None

    client = APIClient()

    # obtain JWT tokens (adjust URL if your token endpoint differs)
    token_resp = client.post("/api/v1/token/", {"email": "mfa@example.com", "password": "Pass12345"}, format="json")
    assert token_resp.status_code == 200, f"token endpoint failed: {token_resp.status_code} {getattr(token_resp, 'data', None)}"
    assert "access" in token_resp.data, f"access token missing: {token_resp.data}"
    access = token_resp.data["access"]

    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    # call setup endpoint
    setup_resp = client.post("/api/v1/auth/mfa/setup/", format="json")
    assert setup_resp.status_code == 200, f"setup failed: {setup_resp.status_code} {getattr(setup_resp, 'data', None)}"

    # ensure secret persisted
    u.refresh_from_db()
    assert getattr(u, "totp_secret", None), "totp_secret was not saved on the user"

    # generate current OTP using the persisted secret
    code = pyotp.TOTP(u.totp_secret).now()
    verify_resp = client.post("/api/v1/auth/mfa/verify/", {"otp": code}, format="json")
    assert verify_resp.status_code == 200, f"verify failed: {verify_resp.status_code} {getattr(verify_resp, 'data', None)}"

    # confirm flag in DB if present
    u.refresh_from_db()
    assert getattr(u, "is_mfa_verified", True) is True