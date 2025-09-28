from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.exceptions import ValidationError
from .models import Profile, Personnel, BankAccount
from .serializers import ProfileSerializer, PersonnelSerializer, BankAccountSerializer

class ProfileViewSet(viewsets.ModelViewSet):
    queryset = Profile.objects.all()
    serializer_class = ProfileSerializer
    permission_classes = [IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser)

    def get_queryset(self):
        qs = super().get_queryset()
        user = self.request.user
        if user.is_staff or user.is_superuser:
            return qs
        return qs.filter(user=user)

    # endpoint: /api/v1/manage_personnel/profiles/me/
    @action(detail=False, methods=['get', 'put'], url_path='me', permission_classes=[IsAuthenticated], parser_classes=[MultiPartParser, FormParser])
    def me(self, request):
        profile = getattr(request.user, 'profile', None)
        if request.method == 'GET':
            if profile is None:
                return Response({'detail': 'profile not found'}, status=status.HTTP_404_NOT_FOUND)
            serializer = self.get_serializer(profile)
            return Response(serializer.data)
        # PUT - update fields and optional image upload
        if profile is None:
            return Response({'detail': 'profile not found'}, status=status.HTTP_404_NOT_FOUND)

        data = request.data.copy()
        serializer = self.get_serializer(profile, data=data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class PersonnelViewSet(viewsets.ModelViewSet):
    queryset = Personnel.objects.all()
    serializer_class = PersonnelSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = super().get_queryset()
        user = self.request.user
        if user.is_staff or user.is_superuser:
            return qs
        return qs.filter(profile__user=user)

class BankAccountViewSet(viewsets.ModelViewSet):
    queryset = BankAccount.objects.all()
    serializer_class = BankAccountSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = super().get_queryset()
        user = self.request.user
        if user.is_staff or user.is_superuser:
            return qs
        return qs.filter(profile__user=user)

    def perform_create(self, serializer):
        profile = getattr(self.request.user, "profile", None)
        if profile is None:
            raise ValidationError("Profil lié à l'utilisateur introuvable.")
        serializer.save(profile=profile)