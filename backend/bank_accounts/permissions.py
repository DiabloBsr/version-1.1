# permissions.py
from typing import Any
from rest_framework import permissions
from django.contrib.auth import get_user_model

User = get_user_model()

class IsProfileOwnerOrStaff(permissions.BasePermission):
    """
    Allow access only to staff users or the owner of the related profile.

    Behavior:
    - Staff users are always allowed.
    - Safe methods (GET, HEAD, OPTIONS) are treated the same as write methods here;
      permission is evaluated per-object in has_object_permission.
    - The object can be:
      * a model instance that has a `profile` attribute (common case),
      * the Profile instance itself.
    - The profile may reference the user via `user` (object) or `user_id` (raw PK).
    """

    def _get_profile_from_obj(self, obj: Any):
        # If obj is a Profile instance, return it directly
        model = getattr(obj, "__class__", None)
        if model is not None and getattr(model, "__name__", "").lower() == "profile":
            return obj

        # Otherwise try to get profile attribute
        return getattr(obj, "profile", None)

    def _is_owner(self, request_user: User, profile_obj: Any) -> bool: # type: ignore
        if not profile_obj or request_user is None or not request_user.is_authenticated:
            return False

        # If profile has a direct user relation
        profile_user = getattr(profile_obj, "user", None)
        if profile_user is not None:
            return getattr(profile_user, "id", None) == getattr(request_user, "id", None) or profile_user == request_user

        # Otherwise check for a user_id field on profile
        profile_user_id = getattr(profile_obj, "user_id", None)
        if profile_user_id is not None:
            # Compare string/UUID/int representations safely
            return str(profile_user_id) == str(getattr(request_user, "id", None))

        return False

    def has_permission(self, request, view) -> bool:
        # Require authentication for non-safe access by default; allow unauthenticated to be rejected later
        # Keep this permissive if your views handle authentication differently.
        return True

    def has_object_permission(self, request, view, obj) -> bool:
        # Staff users have full access
        user = getattr(request, "user", None)
        if user and getattr(user, "is_staff", False):
            return True

        profile_obj = self._get_profile_from_obj(obj)
        return self._is_owner(user, profile_obj)