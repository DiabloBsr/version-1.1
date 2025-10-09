# views.py
import logging
from django.db import transaction
from django.contrib.auth import get_user_model
from django.db.models import Q

from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from rest_framework.exceptions import ValidationError
from rest_framework.views import APIView
from rest_framework.throttling import AnonRateThrottle

from .models import Profile, Personnel
from .serializers import ProfileSerializer, PersonnelSerializer

logger = logging.getLogger(__name__)
User = get_user_model()


class ProfileViewSet(viewsets.ModelViewSet):
    queryset = Profile.objects.all()
    serializer_class = ProfileSerializer
    permission_classes = [IsAuthenticated]
    parser_classes = (JSONParser, MultiPartParser, FormParser)

    def get_queryset(self):
        qs = super().get_queryset()
        user = getattr(self.request, "user", None)
        if user and (user.is_staff or user.is_superuser):
            return qs
        return qs.filter(user=user)

    @transaction.atomic
    def perform_create(self, serializer):
        user = getattr(self.request, "user", None)
        if user is None or not user.is_authenticated:
            raise ValidationError("Authentication required to create profile.")

        existing = Profile.objects.filter(user=user).first()
        if existing:
            for attr, value in serializer.validated_data.items():
                setattr(existing, attr, value)
            existing.save()
            self._created_instance = existing
            logger.debug("Updated existing profile %s for user %s", existing.id, user.id)
        else:
            instance = serializer.save(user=user)
            self._created_instance = instance
            logger.debug("Created profile %s for user %s", instance.id, user.id)

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        instance = getattr(self, "_created_instance", None) or serializer.instance
        out_serializer = self.get_serializer(instance)
        headers = self.get_success_headers(out_serializer.data)
        return Response(out_serializer.data, status=status.HTTP_201_CREATED, headers=headers)

    @action(
        detail=False,
        methods=['get', 'put', 'patch'],
        url_path='me',
        permission_classes=[IsAuthenticated],
        parser_classes=[JSONParser, MultiPartParser, FormParser],
    )
    def me(self, request):
        profile = getattr(request.user, 'profile', None)

        if request.method == 'GET':
            if profile is None:
                return Response({'detail': 'profile not found'}, status=status.HTTP_404_NOT_FOUND)
            serializer = self.get_serializer(profile)
            return Response(serializer.data)

        if profile is None:
            serializer = self.get_serializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            serializer.save(user=request.user)
            return Response(serializer.data, status=status.HTTP_201_CREATED)

        partial = request.method == 'PATCH'
        data = request.data.copy()
        serializer = self.get_serializer(profile, data=data, partial=partial)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class PersonnelViewSet(viewsets.ModelViewSet):
    queryset = Personnel.objects.all()
    serializer_class = PersonnelSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = super().get_queryset()
        user = getattr(self.request, "user", None)
        if user and (user.is_staff or user.is_superuser):
            return qs
        return qs.filter(profile__user=user)


class UserExistsView(APIView):
    """
    Public endpoint to check whether a username and/or email already exists.

    GET params:
      - username (optional)
      - email (optional)

    Returns:
      - 400 if neither username nor email provided
      - 200 {"exists": bool} otherwise

    Notes:
      - Permission is AllowAny to let frontends perform client-side checks.
      - Throttling via AnonRateThrottle is applied to limit enumeration attempts.
      - Case-insensitive comparison using iexact.
    """
    permission_classes = [AllowAny]
    throttle_classes = [AnonRateThrottle]

    def get(self, request, *args, **kwargs):
        username = request.query_params.get('username')
        email = request.query_params.get('email')

        if not username and not email:
            return Response(
                {"detail": "Provide username or email as query parameter."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Build OR query; returns True if any match
        qs = User.objects.none()
        if username:
            qs = qs | User.objects.filter(username__iexact=username)
        if email:
            qs = qs | User.objects.filter(email__iexact=email)

        exists = qs.exists()
        return Response({"exists": exists}, status=status.HTTP_200_OK)