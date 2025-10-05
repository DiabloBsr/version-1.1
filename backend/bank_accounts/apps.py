# bank_accounts/apps.py
from django.apps import AppConfig


class BankAccountsConfig(AppConfig):
    name = "bank_accounts"
    verbose_name = "Bank accounts"

    def ready(self):
        try:
            import bank_accounts.signals
        except Exception:
            import logging
            logging.getLogger(__name__).exception("Failed to import bank_accounts.signals")