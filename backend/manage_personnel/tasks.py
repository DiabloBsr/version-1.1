# manage_personnel/tasks.py
from celery import shared_task
from django.utils import timezone
from datetime import timedelta
from django.db.models import Q
from django.conf import settings
from .models import Profile

@shared_task
def mark_inactive_profiles():
    days = getattr(settings, "PROFILE_INACTIVITY_DAYS", 90)
    cutoff = timezone.now() - timedelta(days=days)
    qs = Profile.objects.filter(is_active=True).filter(
        Q(last_active_at__lt=cutoff) | Q(last_active_at__isnull=True, created_at__lt=cutoff)
    )
    count = qs.update(is_active=False)
    return {"marked_inactive": count}