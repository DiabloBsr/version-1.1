# manage_personnel/signals.py
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.conf import settings
from django.db import transaction
from django.contrib.auth.signals import user_logged_in

from .models import Profile
from .utils.activity import touch_profile_activity


@receiver(post_save, sender=settings.AUTH_USER_MODEL)
def create_or_update_user_profile(sender, instance, created, **kwargs):
    """
    On user creation: link an existing orphan profile by email if present,
    otherwise create a fresh profile attached to the user.

    On user update: keep profile.email in sync when it differs.
    """
    if created:
        with transaction.atomic():
            orphan = Profile.objects.filter(user__isnull=True, email__iexact=instance.email).first()
            if orphan:
                orphan.user = instance
                orphan.save(update_fields=["user"])
                return

            Profile.objects.create(
                user=instance,
                email=instance.email,
                role="user",
                prefs={},
            )
    else:
        try:
            profile = instance.profile
        except Profile.DoesNotExist:
            profile = None

        if profile:
            updated = False
            if instance.email and profile.email != instance.email:
                profile.email = instance.email
                updated = True
            if updated:
                profile.save(update_fields=["email"])


@receiver(user_logged_in)
def on_user_logged_in(sender, user, request, **kwargs):
    """
    Met à jour last_active_at et réactive le profile si nécessaire
    à chaque connexion utilisateur authentifiée.
    """
    try:
        profile = getattr(user, "profile", None)
        if profile:
            # touch_profile_activity met à jour last_active_at et is_active
            touch_profile_activity(profile)
    except Exception:
        # Ne pas planter le flow d'authentification si l'opération échoue
        pass