# manage_personnel/signals.py
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.conf import settings
from .models import Profile

@receiver(post_save, sender=settings.AUTH_USER_MODEL)
def create_or_update_user_profile(sender, instance, created, **kwargs):
    if created:
        Profile.objects.create(
            user=instance,
            email=instance.email,
            role="user",         # ✅ rôle par défaut
            prefs={}             # ✅ initialisation des préférences
        )
    else:
        if hasattr(instance, "profile"):
            profile = instance.profile
            updated = False
            if profile.email != instance.email:
                profile.email = instance.email
                updated = True
            if updated:
                profile.save(update_fields=["email"])