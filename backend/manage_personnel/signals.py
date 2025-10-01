# manage_personnel/signals.py
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.conf import settings
from django.db import transaction
from .models import Profile

@receiver(post_save, sender=settings.AUTH_USER_MODEL)
def create_or_update_user_profile(sender, instance, created, **kwargs):
    """
    On user creation: link an existing orphan profile by email if present,
    otherwise create a fresh profile attached to the user.

    On user update: keep profile.email in sync when it differs.
    """
    # defensive: prefer atomic operation for create/link
    if created:
        with transaction.atomic():
            # try to find an orphan profile with the same email (case-insensitive)
            orphan = Profile.objects.filter(user__isnull=True, email__iexact=instance.email).first()
            if orphan:
                orphan.user = instance
                orphan.save(update_fields=["user"])
                return

            # create a new profile attached to the user
            Profile.objects.create(
                user=instance,
                email=instance.email,
                role="user",
                prefs={},  # ensure prefs field accepts dict; prefer JSONField on model
            )
    else:
        # keep profile email synchronized if a profile exists
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