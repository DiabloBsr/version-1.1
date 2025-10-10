import pytest
from django.utils import timezone
from rest_framework.test import APIClient
from activities.models import Activity 

@pytest.mark.django_db
def test_create_activity_success(active_user):
    client = APIClient()
    client.force_authenticate(user=active_user)

    payload = {
        "text": "User logged in",
        "type": "login",
        "meta": {"ip": "127.0.0.1"},
    }
    response = client.post("/api/v1/activities/", payload, format="json")

    assert response.status_code == 201
    data = response.json()
    assert data["text"] == "User logged in"
    assert data["type"] == "login"
    # ✅ Correction ici
    assert data["user"] == str(active_user.id)
    assert Activity.objects.filter(user=active_user, text="User logged in").exists()