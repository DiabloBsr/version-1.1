from django.contrib import admin
from .models import Activity

@admin.register(Activity)
class ActivityAdmin(admin.ModelAdmin):
    list_display = ('id', 'user', 'type', 'timestamp', 'created_at', 'external_id', 'visible')
    list_filter = ('type', 'visible', 'created_at')
    search_fields = ('text', 'meta', 'external_id', 'user__email', 'user__username')
    readonly_fields = ('created_at',)
    ordering = ('-timestamp',)