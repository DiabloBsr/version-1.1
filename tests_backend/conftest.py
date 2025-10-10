import pytest
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

User = get_user_model()


@pytest.fixture
def api_client():
    """Client DRF prêt à l’emploi pour tester les vues."""
    return APIClient()


@pytest.fixture
def active_user(db):
    """Crée un utilisateur actif avec profil lié (profil auto-créé par signal)."""
    user = User.objects.create_user(
        username="testuser",
        email="test@example.com",
        password="password123"
    )
    user.profile.is_active = True
    user.profile.save()
    return user


@pytest.fixture
def inactive_user(db):
    """Crée un utilisateur inactif avec profil lié (profil auto-créé par signal)."""
    user = User.objects.create_user(
        username="inactive",
        email="inactive@example.com",
        password="password123"
    )
    user.profile.is_active = False
    user.profile.save()
    return user


@pytest.fixture
def user(db):
    """Crée un utilisateur générique avec profil lié (profil auto-créé par signal)."""
    user = User.objects.create_user(
        email="user@example.com",
        password="Pass12345",
        username="user"
    )
    user.profile.is_active = True
    user.profile.save()
    return user