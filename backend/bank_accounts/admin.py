from django.contrib import admin

# Register your models here.
# bank_accounts/admin.py
from django.contrib import admin
from .models import BankAccount, BankTransaction, BankAudit

@admin.register(BankAccount)
class BankAccountAdmin(admin.ModelAdmin):
    list_display = ("id", "profile", "bank_name", "masked_account", "is_primary", "status", "created_at")
    list_filter = ("is_primary", "status", "bank_name")
    search_fields = ("masked_account", "bank_name", "bank_code", "iban_normalized")
    readonly_fields = ("masked_account", "iban_normalized", "created_at", "updated_at")

@admin.register(BankTransaction)
class BankTransactionAdmin(admin.ModelAdmin):
    list_display = ("id", "bank_account", "type", "amount", "timestamp")
    search_fields = ("external_reference", "description")

@admin.register(BankAudit)
class BankAuditAdmin(admin.ModelAdmin):
    list_display = ("id", "action", "actor", "target_type", "target_id", "created_at")
    readonly_fields = ("detail", "created_at")