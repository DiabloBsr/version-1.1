# bank_accounts/models.py
"""
BankAccount, BankTransaction and BankAudit models.

- EncryptedTextField is used to store sensitive plaintext encrypted at-rest.
- Meta.db_table keeps predictable table names (public schema).
- All timestamps use timezone-aware defaults.
- save() ensures masked_account and iban_normalized are maintained.
- OneToOne relation enforces un compte bancaire par Profile.
- Adjust related_name values to avoid collisions with other apps.
"""

import uuid
from typing import Optional

from django.conf import settings
from django.db import models, transaction
from django.utils import timezone

from .fields import EncryptedTextField


def _mask_value(value: Optional[str]) -> str:
    if not value:
        return ""
    s = str(value).strip()
    if len(s) <= 8:
        if len(s) <= 4:
            return s
        return s[:2] + "*" * max(0, len(s) - 4) + s[-2:]
    return s[:4] + "*" * max(6, len(s) - 8) + s[-4:]


def _normalize_iban(iban: Optional[str]) -> Optional[str]:
    if not iban:
        return None
    return "".join([c for c in str(iban).upper() if c.isalnum()])


class BankAccount(models.Model):
    """
    Primary bank account model.
    - `iban_encrypted` and `account_number_encrypted` store encrypted plaintext.
    - `masked_account` is derived for safe display.
    - `iban_normalized` is stored for fast search/lookups.
    - OneToOneField enforces un compte par profile au niveau DB.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    profile = models.OneToOneField(
        "manage_personnel.Profile",
        on_delete=models.CASCADE,
        related_name="bank_account",
        related_query_name="bank_account",
    )

    label = models.CharField(max_length=120, blank=True)
    bank_name = models.CharField(max_length=120, blank=True)
    bank_code = models.CharField(max_length=64, blank=True, null=True)
    agency = models.CharField(max_length=64, blank=True, null=True)
    currency = models.CharField(max_length=8, blank=True, default="EUR")

    # Encrypted sensitive values (EncryptedTextField must return plaintext when accessed)
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
            models.Index(fields=["iban_normalized"]),
        ]

    def __str__(self) -> str:
        # Prefer profile username or name when available for readable display
        profile_obj = getattr(self, "profile", None)
        profile_ident = None
        try:
            if profile_obj:
                profile_ident = getattr(profile_obj, "username", None) or getattr(profile_obj, "name", None) or getattr(profile_obj, "full_name", None)
        except Exception:
            profile_ident = None
        display = self.masked_account or self.label or str(self.id)
        profile_display = profile_ident or getattr(profile_obj, "id", None) or getattr(profile_obj, "pk", None) or "profile"
        return f"{profile_display} - {display}"

    def set_iban(self, iban: Optional[str]) -> None:
        """
        Set IBAN plaintext into the encrypted field, compute normalized and masked values.
        Call this before save() when accepting an IBAN from input.
        """
        if not iban:
            self.iban_encrypted = None
            self.iban_normalized = None
            return
        normalized = _normalize_iban(iban)
        self.iban_normalized = normalized
        self.iban_encrypted = iban
        self.masked_account = _mask_value(iban)

    @property
    def account_number(self) -> Optional[str]:
        """Convenience property returning decrypted account number (via EncryptedTextField)."""
        return self.account_number_encrypted

    @transaction.atomic
    def save(self, *args, **kwargs):
        """
        Ensure derived fields are consistent before saving.
        - Prefer explicit decrypted values if EncryptedTextField returns plaintext on access.
        - Avoid unnecessary writes when masked_account is already correct.
        """
        # Prefer account number for masking; fallback to IBAN plaintext if present
        acct_plain = None
        try:
            acct_plain = self.account_number_encrypted or self.iban_encrypted
        except Exception:
            acct_plain = None

        computed_mask = _mask_value(acct_plain)
        if not self.masked_account or self.masked_account != computed_mask:
            self.masked_account = computed_mask

        # Ensure iban_normalized is set if IBAN plaintext present
        if getattr(self, "iban_encrypted", None) and not self.iban_normalized:
            try:
                self.iban_normalized = _normalize_iban(self.iban_encrypted)
            except Exception:
                self.iban_normalized = None

        super().save(*args, **kwargs)


class BankTransaction(models.Model):
    """
    Transactions related to a BankAccount.
    Keep them light and indexed for queries.
    """

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
        related_name="bank_transactions",
        related_query_name="bank_transaction",
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
    """
    Audit trail for bank-related actions.
    Store identifiers and non-sensitive metadata only.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="bank_audits"
    )
    action = models.CharField(max_length=128)  # e.g. bank_account.create, bank_account.delete
    target_type = models.CharField(max_length=64, blank=True, null=True)  # e.g. BankAccount
    target_id = models.CharField(max_length=64, blank=True, null=True)  # UUID or PK as string
    detail = models.JSONField(blank=True, null=True)  # contextual metadata, must not contain secrets
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