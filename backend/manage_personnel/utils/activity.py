# manage_personnel/utils/activity.py
from django.utils import timezone
from django.db import transaction
from typing import Optional

from manage_personnel.models import Profile

def touch_profile_activity(profile: Optional[Profile], touch_time=None) -> Optional[Profile]:
    """
    Met à jour profile.last_active_at et réactive le profile si nécessaire.

    Comportement
    - Si profile est None, ne fait rien.
    - Définit last_active_at = touch_time (ou maintenant si None).
    - Si profile.is_active est False, le met à True.
    - Utilise transaction.atomic et refresh_from_db pour éviter les conditions de course.

    Appel recommandé
    - Sur authentification réussie (user_logged_in signal).
    - Lorsqu'un administrateur consulte/modifie un profil (si cela compte comme activité).
    - Lorsqu'un utilisateur authentifié consulte sa page profil via l'API.
    - Ne pas appeler pour requêtes publiques non authentifiées.
    """
    if profile is None:
        return None

    if touch_time is None:
        touch_time = timezone.now()

    with transaction.atomic():
        try:
            profile.refresh_from_db(fields=["is_active", "last_active_at"])
        except Exception:
            # Si refresh échoue (rare), on continue quand même
            pass

        # Met à jour la date du dernier accès
        profile.last_active_at = touch_time

        # Réactive le profil si nécessaire
        if not getattr(profile, "is_active", True):
            profile.is_active = True
            # TODO: ajouter audit log ici si nécessaire (qui, pourquoi, timestamp)

        # Sauvegarde uniquement les champs modifiés
        try:
            profile.save(update_fields=["last_active_at", "is_active"])
        except Exception:
            # En cas d'erreur de sauvegarde, on laisse l'exception remonter en dev,
            # mais en production on peut logger et ignorer selon la politique.
            raise

    return profile