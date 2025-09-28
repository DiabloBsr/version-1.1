import pytest
from django.urls import reverse
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

User = get_user_model()

@pytest.mark.django_db
def test_register_and_token_flow(settings):
    client = APIClient()

    # Register
    url = reverse("accounts:register")
    data = {"email": "testuser@example.com", "password": "StrongPass123", "first_name": "T", "last_name": "U"}
    r = client.post(url, data, format="json")
    assert r.status_code == 201
    assert User.objects.filter(email="testuser@example.com").exists()

    # Obtain token (token endpoints usually registered at /api/v1/token/)
    token_url = "/api/v1/token/"
    r = client.post(token_url, {"email": "testuser@example.com", "password": "StrongPass123"}, format="json")
    assert r.status_code == 200
    assert "access" in r.data and "refresh" in r.data

    # Logout (blacklist) using refresh token; need authenticated user to call logout
    access = r.data["access"]
    refresh = r.data["refresh"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    logout_url = reverse("accounts:logout")
    r = client.post(logout_url, {"refresh": refresh}, format="json")
    # Expect success 205 or 200 depending on implementation
    assert r.status_code in (200, 205)