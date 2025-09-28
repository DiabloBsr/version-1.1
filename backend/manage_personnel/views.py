from django.db import transaction
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError

from .models import Profile, Personnel, BankAccount
from .serializers import ProfileSerializer, PersonnelSerializer, BankAccountSerializer


class ProfileViewSet(viewsets.ModelViewSet):
    """Gestion des profils utilisateurs."""
    queryset = Profile.objects.all()
    serializer_class = ProfileSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        """
        Restreindre aux profils de l'utilisateur connecté,
        sauf si l'utilisateur est admin.
        """
        qs = super().get_queryset()
        user = self.request.user
        if user.is_staff or user.is_superuser:
            return qs
        return qs.filter(user=user)


class PersonnelViewSet(viewsets.ModelViewSet):
    """Gestion des personnels liés aux profils."""
    queryset = Personnel.objects.all()
    serializer_class = PersonnelSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        """
        Restreindre aux personnels liés au profil de l'utilisateur connecté.
        """
        qs = super().get_queryset()
        user = self.request.user
        if user.is_staff or user.is_superuser:
            return qs
        return qs.filter(profile__user=user)


class BankAccountViewSet(viewsets.ModelViewSet):
    """Gestion des comptes bancaires liés aux profils."""
    queryset = BankAccount.objects.all()
    serializer_class = BankAccountSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        """
        Restreindre aux comptes bancaires liés au profil de l'utilisateur connecté.
        """
        qs = super().get_queryset()
        user = self.request.user
        if user.is_staff or user.is_superuser:
            return qs
        return qs.filter(profile__user=user)

    def perform_create(self, serializer):
        """
        Associer automatiquement le compte bancaire au profil de l'utilisateur connecté.
        """
        profile = getattr(self.request.user, "profile", None)
        if profile is None:
            raise ValidationError("Profil lié à l'utilisateur introuvable.")
        serializer.save(profile=profile)

    @action(detail=True, methods=["post"])
    def set_primary(self, request, pk=None):
        """
        Définit ce compte comme principal pour son profil et désactive les autres.
        """
        account = self.get_object()
        profile = account.profile

        if not profile:
            raise ValidationError("Le compte n'est associé à aucun profil.")

        with transaction.atomic():
            # désactiver les autres comptes
            BankAccount.objects.filter(profile=profile).exclude(pk=account.pk).update(is_primary=False)
            if not account.is_primary:
                account.is_primary = True
                account.save()

        serializer = self.get_serializer(account)
        return Response(
            {"status": "primary set", "account": serializer.data},
            status=status.HTTP_200_OK,
        )