# bank_accounts/models.py
import uuid
from typing import Optional

from django.conf import settings
from django.db import models
from django.utils import timezone

from .fields import EncryptedTextField


class BankAccount(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    profile = models.ForeignKey(
        "manage_personnel.Profile",
        on_delete=models.CASCADE,
        related_name="bank_accounts_from_bank_accounts_app",
        related_query_name="bank_accounts_from_bank_accounts_app",
    )

    label = models.CharField(max_length=120, blank=True)
    bank_name = models.CharField(max_length=120, blank=True)
    bank_code = models.CharField(max_length=64, blank=True, null=True)
    agency = models.CharField(max_length=64, blank=True, null=True)
    currency = models.CharField(max_length=8, blank=True, default="EUR")

    # Encrypted sensitive values (EncryptedTextField must handle encryption/decryption)
    iban_encrypted = EncryptedTextField(blank=True, null=True)
    account_number_encrypted = EncryptedTextField(blank=True, null=True)

    # Derived / display fields
    iban_normalized = models.CharField(max_length=64, blank=True, null=True, db_index=True)
    masked_account = models.CharField(max_length=64, blank=True, null=True, db_index=True)

    # Status and verification metadata
    status = models.CharField(max_length=32, default="active", db_index=True)
    is_primary = models.BooleanField(default=False)
    verification_metadata = models.JSONField(blank=True, null=True)
    verified_at = models.DateTimeField(blank=True, null=True)

    created_at = models.DateTimeField(default=timezone.now, editable=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "bank_account"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["profile"]),
            models.Index(fields=["masked_account"]),
            models.Index(fields=["status"]),
        ]

    def __str__(self) -> str:
        display = self.masked_account or self.label or str(self.id)
        profile_id = getattr(self.profile, "id", None) or getattr(self.profile, "pk", None)
        return f"{profile_id} - {display}"

    def _mask_iban(self, value: Optional[str]) -> str:
        if not value:
            return ""
        s = str(value).strip()
        if len(s) <= 8:
            if len(s) <= 4:
                return s
            return s[:2] + "*" * max(0, len(s) - 4) + s[-2:]
        return s[:4] + "*" * max(6, len(s) - 8) + s[-4:]

    def set_iban(self, iban: Optional[str]) -> None:
        if not iban:
            self.iban_encrypted = None
            self.iban_normalized = None
            self.masked_account = None
            return

        normalized = "".join([c for c in str(iban).upper() if c.isalnum()])
        self.iban_normalized = normalized
        # store plaintext into the EncryptedTextField which must handle encryption internally
        self.iban_encrypted = iban
        self.masked_account = self._mask_iban(iban)

    @property
    def account_number(self) -> Optional[str]:
        return self.account_number_encrypted

    def save(self, *args, **kwargs):
        # Ensure masked_account is populated from decrypted fields if needed
        acct = None
        # Prefer explicit decrypted values if EncryptedTextField returns plaintext
        try:
            acct = self.account_number_encrypted or self.iban_encrypted
        except Exception:
            acct = None
        try:
            computed = self._mask_iban(acct)
        except Exception:
            computed = (acct or "")[:4] + "..." if acct else ""
        if not self.masked_account or self.masked_account != computed:
            self.masked_account = computed
        super().save(*args, **kwargs)


class BankTransaction(models.Model):
    TYPE_CHOICES = [
        ("credit", "Credit"),
        ("debit", "Debit"),
        ("fee", "Fee"),
        ("refund", "Refund"),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    bank_account = models.ForeignKey(
        "bank_accounts.BankAccount", on_delete=models.CASCADE, related_name="transactions"
    )

    profile = models.ForeignKey(
        "manage_personnel.Profile",
        on_delete=models.CASCADE,
        related_name="bank_transaction_profiles",
        related_query_name="bank_transaction_profiles",
        null=True,
        blank=True,
    )

    type = models.CharField(max_length=32, choices=TYPE_CHOICES)
    amount = models.DecimalField(max_digits=18, decimal_places=2)
    currency = models.CharField(max_length=8, default="EUR")
    description = models.TextField(blank=True, null=True)
    external_reference = models.CharField(max_length=255, blank=True, null=True)

    timestamp = models.DateTimeField(default=timezone.now, db_index=True)
    balance_after = models.DecimalField(max_digits=18, decimal_places=2, blank=True, null=True)
    meta = models.JSONField(blank=True, null=True)

    created_at = models.DateTimeField(default=timezone.now, editable=False)

    class Meta:
        db_table = "bank_transaction"
        ordering = ["-timestamp"]
        indexes = [
            models.Index(fields=["bank_account"]),
            models.Index(fields=["profile"]),
            models.Index(fields=["timestamp"]),
        ]

    def __str__(self) -> str:
        return f"{self.type} {self.amount} {self.currency} @ {self.timestamp}"


class BankAudit(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="bank_audits"
    )
    action = models.CharField(max_length=128)
    target_type = models.CharField(max_length=64, blank=True, null=True)
    target_id = models.CharField(max_length=64, blank=True, null=True)
    detail = models.JSONField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now, editable=False)

    class Meta:
        db_table = "bank_account_audit"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["actor"]),
            models.Index(fields=["action"]),
            models.Index(fields=["target_type", "target_id"]),
            models.Index(fields=["created_at"]),
        ]

    def __str__(self) -> str:
        actor_id = getattr(self.actor, "id", None) or getattr(self.actor, "pk", None) or "system"
        return f"{self.action} target={self.target_type}:{self.target_id} by {actor_id} at {self.created_at}"