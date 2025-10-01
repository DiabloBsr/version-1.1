from django.conf import settings
from django.db import models
from django.utils import timezone


class Activity(models.Model):
    """
    Audit / user activity record.

    Fields:
    - user: FK to the authenticated user that triggered the activity
    - text: human readable description
    - type: short tag for filtering (profile_change, transaction, login, etc.)
    - meta: optional structured JSON payload with details (field, old, new, ...)
    - timestamp: logical time of the event (client-provided or server time)
    - created_at: moment the record was persisted on the server
    - external_id: optional stable identifier from client or external systems (helps deduplication)
    - visible: soft-delete / visibility flag
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="activities",
        db_index=True,
    )
    text = models.TextField()
    type = models.CharField(max_length=64, blank=True, null=True, db_index=True)
    meta = models.JSONField(blank=True, null=True)
    timestamp = models.DateTimeField(
        default=timezone.now,
        help_text="Logical time of the event; client may supply; server uses now() if absent",
        db_index=True,
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    external_id = models.CharField(
        max_length=128,
        blank=True,
        null=True,
        db_index=True,
        help_text="Optional client/external id for deduplication",
    )
    visible = models.BooleanField(
        default=True, help_text="Soft visibility flag; set False to hide without deleting"
    )

    class Meta:
        ordering = ["-timestamp", "-created_at"]
        indexes = [
            models.Index(fields=["user", "-timestamp"]),
            models.Index(fields=["user", "created_at"]),
            models.Index(fields=["external_id"]),
        ]
        verbose_name = "Activity"
        verbose_name_plural = "Activities"

    def __str__(self):
        short = (self.text[:75] + ("…" if len(self.text) > 75 else "")) if self.text else ""
        return f"Activity(user={self.user}, type={self.type or 'n/a'}, ts={self.timestamp.isoformat()}, text={short})"