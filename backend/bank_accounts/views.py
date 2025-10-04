from django.shortcuts import render

# Create your views here.
# bank_accounts/views.py
from rest_framework import viewsets, permissions, status
from rest_framework.response import Response
from rest_framework.decorators import action
from django.shortcuts import get_object_or_404
from .models import BankAccount
from .serializers import BankAccountCreateSerializer, BankAccountDetailSerializer

class IsOwnerOrStaff(permissions.BasePermission):
    def has_object_permission(self, request, view, obj):
        if request.user.is_staff:
            return True
        # assume Profile has a user relation or user_id attribute
        profile = getattr(obj, "profile", None)
        if profile is None:
            return False
        return getattr(profile, "user_id", None) == getattr(request.user, "id", None) or getattr(profile, "user", None) == request.user

class BankAccountViewSet(viewsets.ModelViewSet):
    queryset = BankAccount.objects.all().select_related("profile")
    permission_classes = [permissions.IsAuthenticated]
    lookup_field = "id"

    def get_serializer_class(self):
        if self.action in ("create",):
            return BankAccountCreateSerializer
        return BankAccountDetailSerializer

    def get_queryset(self):
        user = self.request.user
        if user.is_staff:
            return super().get_queryset()
        # restrict to profiles owned by user - assumes Profile model has user relation
        return super().get_queryset().filter(profile__user=user)

    def perform_create(self, serializer):
        return serializer.save()

    def destroy(self, request, *args, **kwargs):
        obj = self.get_object()
        # soft-delete pattern: mark status deleted instead of hard delete, if desired
        obj.status = "deleted"
        obj.is_primary = False
        obj.save()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsOwnerOrStaff])
    def make_primary(self, request, id=None):
        account = self.get_object()
        BankAccount.objects.filter(profile=account.profile, is_primary=True).update(is_primary=False)
        account.is_primary = True
        account.save()
        return Response({"status": "ok"})