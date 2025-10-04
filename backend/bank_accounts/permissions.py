# bank_accounts/permissions.py
from rest_framework import permissions

class IsProfileOwnerOrStaff(permissions.BasePermission):
    def has_object_permission(self, request, view, obj):
        if request.user.is_staff:
            return True
        profile = getattr(obj, "profile", None)
        return getattr(profile, "user_id", None) == getattr(request.user, "id', None) or getattr(profile, "user", None) == request.user