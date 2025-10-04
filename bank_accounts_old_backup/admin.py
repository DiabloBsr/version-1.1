# bank_accounts/admin.py
from django.contrib import admin
from .models import BankAccount, BankTransaction, BankAudit


@admin.register(BankAccount)
class BankAccountAdmin(admin.ModelAdmin):
    list_display = ("id", "label", "profile", "masked_account", "iban_normalized", "status", "is_primary", "created_at")
    list_filter = ("status", "currency", "is_primary")
    search_fields = ("masked_account", "iban_normalized", "bank_name", "label", "profile__user__email")
    readonly_fields = ("masked_account", "iban_normalized", "created_at", "updated_at")
    ordering = ("-created_at",)
    list_select_related = ("profile",)


@admin.register(BankTransaction)
class BankTransactionAdmin(admin.ModelAdmin):
    list_display = ("id", "bank_account", "profile", "type", "amount", "currency", "timestamp")
    search_fields = ("external_reference", "description", "bank_account__masked_account")
    list_filter = ("type", "currency")
    list_select_related = ("bank_account", "profile")


@admin.register(BankAudit)
class BankAuditAdmin(admin.ModelAdmin):
    list_display = ("id", "actor", "action", "target_type", "target_id", "created_at")
    search_fields = ("action", "detail")
    readonly_fields = ("created_at",)
    ordering = ("-created_at",)
    list_select_related = ("actor",)