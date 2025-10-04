from typing import Any, Dict, Optional
from django.shortcuts import get_object_or_404
from django.db import transaction
from django.utils import timezone
from rest_framework import viewsets, status, permissions, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.request import Request
from rest_framework import serializers

from .models import BankAccount, BankTransaction, BankAudit
from .serializers import (
    BankAccountListSerializer,
    BankAccountDetailSerializer,
    BankAccountCreateUpdateSerializer,
    BankTransactionSerializer,
)
from manage_personnel.models import Profile


class IsOwnerOrAdmin(permissions.BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated)

    def has_object_permission(self, request, view, obj: BankAccount):
        try:
            profile_user_id = getattr(obj.profile, "user_id", None) or (
                getattr(obj.profile, "user", None) and getattr(obj.profile.user, "id", None)
            )
        except Exception:
            profile_user_id = None
        return bool(request.user.is_staff or (profile_user_id is not None and profile_user_id == getattr(request.user, "id", None)))


def log_audit(actor, action: str, target: Optional[BankAccount] = None, detail: Optional[Dict] = None) -> None:
    try:
        BankAudit.objects.create(
            actor=actor if getattr(actor, "is_authenticated", True) else None,
            action=action,
            target_type="BankAccount" if isinstance(target, BankAccount) else (getattr(target, "__class__", None).__name__ if target else None),
            target_id=getattr(target, "id", None) if target else None,
            detail=detail or {},
            created_at=timezone.now(),
        )
    except Exception:
        return


class BankAccountViewSet(viewsets.ModelViewSet):
    queryset = BankAccount.objects.all().select_related("profile")
    permission_classes = [permissions.IsAuthenticated, IsOwnerOrAdmin]
    lookup_field = "id"

    def get_serializer_class(self):
        if self.action == "list":
            return BankAccountListSerializer
        if self.action in ("create", "update", "partial_update"):
            return BankAccountCreateUpdateSerializer
        return BankAccountDetailSerializer

    def get_queryset(self):
        user = self.request.user
        if user.is_staff:
            return BankAccount.objects.all().select_related("profile")
        profiles = Profile.objects.filter(user_id=getattr(user, "id", None))
        return BankAccount.objects.filter(profile__in=profiles)

    def perform_create(self, serializer: serializers.ModelSerializer):
        user = self.request.user
        profile_id = self.request.data.get("profile")
        profile_obj = None
        if profile_id:
            profile_obj = get_object_or_404(Profile, pk=profile_id)
        else:
            profile_obj = Profile.objects.filter(user_id=getattr(user, "id", None)).first()
            if profile_obj is None:
                raise serializers.ValidationError("No profile found for current user; provide profile id.")
        serializer.save(profile=profile_obj)
        log_audit(actor=user, action="bank_account.create", target=serializer.instance, detail={"profile_id": getattr(profile_obj, "id", None)})

    def perform_update(self, serializer: serializers.ModelSerializer):
        serializer.save()
        log_audit(actor=self.request.user, action="bank_account.update", target=serializer.instance, detail={"updated_by": getattr(self.request.user, "id", None)})

    def perform_destroy(self, instance: BankAccount):
        log_audit(actor=self.request.user, action="bank_account.delete", target=instance, detail={})
        instance.delete()

    @action(detail=True, methods=["post"], url_path="reveal", permission_classes=[permissions.IsAuthenticated, IsOwnerOrAdmin])
    def reveal(self, request: Request, id=None):
        account = get_object_or_404(self.get_queryset(), pk=id)
        log_audit(actor=request.user, action="bank_account.reveal", target=account, detail={"remote_addr": request.META.get("REMOTE_ADDR")})
        data: Dict[str, Any] = {
            "id": str(account.id),
            "iban": account.iban_encrypted,
            "account_number": account.account_number_encrypted,
            "masked_account": account.masked_account,
        }
        return Response(data)


class BankTransactionViewSet(mixins.CreateModelMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    queryset = BankTransaction.objects.all().select_related("bank_account", "profile")
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = BankTransactionSerializer
    lookup_field = "id"

    def get_queryset(self):
        user = self.request.user
        if user.is_staff:
            return BankTransaction.objects.all()
        profiles = Profile.objects.filter(user_id=getattr(user, "id", None)).values_list("id", flat=True)
        return BankTransaction.objects.filter(profile_id__in=profiles) | BankTransaction.objects.filter(bank_account__profile__in=profiles)

    def perform_create(self, serializer: serializers.ModelSerializer):
        user = self.request.user
        profile = serializer.validated_data.get("profile")
        if profile is None:
            profile = Profile.objects.filter(user_id=getattr(user, "id", None)).first()
        serializer.save(profile=profile)
        try:
            log_audit(actor=user, action="bank_transaction.create", detail={"external_reference": serializer.validated_data.get("external_reference")})
        except Exception:
            pass