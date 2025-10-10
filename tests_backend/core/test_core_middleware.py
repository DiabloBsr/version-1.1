import pytest
from django.test import RequestFactory
from django.utils import timezone
from datetime import timedelta
from backend.core.middleware import InactivityMiddleware


@pytest.mark.django_db
def test_inactivity_middleware_deactivates_old_user(active_user, settings):
    """
    Vérifie que le middleware désactive automatiquement un utilisateur
    dont le profil est inactif depuis plus longtemps que la limite définie.
    """
    settings.PROFILE_INACTIVITY_DAYS = 30

    # Simuler un utilisateur inactif depuis 60 jours
    active_user.profile.last_active_at = timezone.now() - timedelta(days=60)
    active_user.profile.is_active = True
    active_user.profile.save()

    factory = RequestFactory()
    request = factory.get("/")
    request.user = active_user

    middleware = InactivityMiddleware(lambda r: r)
    middleware(request)

    # Recharger depuis la base
    active_user.profile.refresh_from_db()
    assert active_user.profile.is_active is False


@pytest.mark.django_db
def test_inactivity_middleware_keeps_recent_user_active(active_user, settings):
    """
    Vérifie que le middleware garde actif un utilisateur
    dont l'activité est encore récente.
    """
    settings.PROFILE_INACTIVITY_DAYS = 30

    # Simuler une activité récente (hier)
    active_user.profile.last_active_at = timezone.now() - timedelta(days=1)
    active_user.profile.is_active = True
    active_user.profile.save()

    factory = RequestFactory()
    request = factory.get("/")
    request.user = active_user

    middleware = InactivityMiddleware(lambda r: r)
    middleware(request)

    active_user.profile.refresh_from_db()
    assert active_user.profile.is_active is True


@pytest.mark.django_db
def test_inactivity_middleware_updates_last_active_at(active_user, settings):
    """
    Vérifie que le middleware met bien à jour last_active_at
    à chaque requête.
    """
    settings.PROFILE_INACTIVITY_DAYS = 30

    old_time = timezone.now() - timedelta(days=5)
    active_user.profile.last_active_at = old_time
    active_user.profile.save()

    factory = RequestFactory()
    request = factory.get("/")
    request.user = active_user

    middleware = InactivityMiddleware(lambda r: r)
    middleware(request)

    active_user.profile.refresh_from_db()
    assert active_user.profile.last_active_at > old_time