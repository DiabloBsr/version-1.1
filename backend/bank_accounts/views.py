# bank_accounts/views.py
from rest_framework import viewsets, permissions, status
from rest_framework.response import Response
from rest_framework.decorators import action
from django.shortcuts import get_object_or_404
from django.db import transaction

from .models import BankAccount
from .serializers import (
    BankAccountCreateSerializer,
    BankAccountDetailSerializer,
    BankAccountUpdateSerializer,
)


class IsOwnerOrStaff(permissions.BasePermission):
    """
    Permission object ensuring only staff or the owner of the profile can operate on the account.
    Assumes Profile model exposes either .user or .user_id pointing to the user.
    """

    def has_object_permission(self, request, view, obj):
        if request.user.is_staff:
            return True
        profile = getattr(obj, "profile", None)
        if profile is None:
            return False
        return getattr(profile, "user_id", None) == getattr(request.user, "id", None) or getattr(profile, "user", None) == request.user


class BankAccountViewSet(viewsets.ModelViewSet):
    """
    ViewSet for BankAccount:
    - create -> BankAccountCreateSerializer
    - update/partial_update -> BankAccountUpdateSerializer (applies encryption helpers)
    - retrieve/list -> BankAccountDetailSerializer
    """
    queryset = BankAccount.objects.all().select_related("profile")
    permission_classes = [permissions.IsAuthenticated, IsOwnerOrStaff]
    lookup_field = "id"

    def get_serializer_class(self):
        if self.action == "create":
            return BankAccountCreateSerializer
        if self.action in ("update", "partial_update"):
            return BankAccountUpdateSerializer
        return BankAccountDetailSerializer

    def get_queryset(self):
        user = self.request.user
        if user.is_staff:
            return super().get_queryset()
        # restrict to profiles owned by user - assumes Profile model has user relation
        return super().get_queryset().filter(profile__user=user)

    def perform_create(self, serializer):
        """
        Creation logic is handled in serializer.create (calls set_iban etc).
        """
        return serializer.save()

    def perform_update(self, serializer):
        """
        Apply encrypted-field helpers and unique-primary handling on update.
        We operate on the instance to avoid exposing encrypted storage fields directly.
        """
        instance: BankAccount = serializer.instance
        data = serializer.validated_data.copy()

        # Extract and consume write-only encrypted inputs
        iban = data.pop("iban", None)
        acct = data.pop("account_number", None)

        # Manage is_primary before saving instance so uniqueness is preserved
        is_primary = data.get("is_primary", None)
        if is_primary is True:
            # unset other primary accounts for this profile atomically
            BankAccount.objects.filter(profile=instance.profile, is_primary=True).exclude(id=instance.id).update(is_primary=False)

        # Apply non-encrypted fields from validated_data
        for field, val in data.items():
            # skip None values to allow partial_update semantics
            if val is None:
                continue
            setattr(instance, field, val)

        # Apply IBAN/account updates using model helpers to ensure masked/normalized values
        if iban is not None:
            instance.set_iban(iban)

        if acct is not None:
            instance.account_number_encrypted = acct
            # save() will recompute masked_account if necessary

        # Save instance inside transaction
        with transaction.atomic():
            instance.save()

        return instance

    def destroy(self, request, *args, **kwargs):
        """
        Soft-delete pattern: mark status deleted and unset primary flag.
        """
        obj = self.get_object()
        obj.status = "deleted"
        obj.is_primary = False
        obj.save()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsOwnerOrStaff])
    def make_primary(self, request, id=None):
        account = self.get_object()
        BankAccount.objects.filter(profile=account.profile, is_primary=True).exclude(id=account.id).update(is_primary=False)
        account.is_primary = True
        account.save()
        return Response({"status": "ok"})