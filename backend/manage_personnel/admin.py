# manage_personnel/admin.py
from django.contrib import admin
from .models import Profile

@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "nom", "prenom", "is_active", "last_active_at", "created_at")
    list_filter = ("is_active",)
    search_fields = ("nom", "prenom", "user__email")