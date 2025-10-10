from django.utils import timezone
from datetime import timedelta
from django.conf import settings


class InactivityMiddleware:
    """
    Vérifie à chaque requête si l'utilisateur connecté est inactif
    depuis trop longtemps et désactive son profil si nécessaire.
    """
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        user = getattr(request, "user", None)

        if user and user.is_authenticated and hasattr(user, "profile"):
            profile = user.profile
            days = getattr(settings, "PROFILE_INACTIVITY_DAYS", 90)
            cutoff = timezone.now() - timedelta(days=days)

            updated_fields = []

            # Vérifier l'inactivité
            if profile.last_active_at and profile.last_active_at < cutoff:
                if profile.is_active:
                    profile.is_active = False
                    updated_fields.append("is_active")
            else:
                # Si encore dans les délais, on s'assure qu'il reste actif
                if not profile.is_active:
                    profile.is_active = True
                    updated_fields.append("is_active")

            # Mettre à jour la date de dernière activité
            profile.last_active_at = timezone.now()
            updated_fields.append("last_active_at")

            if updated_fields:
                profile.save(update_fields=updated_fields)

        return self.get_response(request)