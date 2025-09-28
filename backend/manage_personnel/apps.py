from django.apps import AppConfig

class ManagePersonnelConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "manage_personnel"

    def ready(self):
        import manage_personnel.signals