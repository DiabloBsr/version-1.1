# accounts/views.py
import logging
from django.contrib.auth.forms import PasswordResetForm
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.generics import CreateAPIView
from rest_framework_simplejwt.tokens import RefreshToken, TokenError
from rest_framework.throttling import SimpleRateThrottle

from .serializers import RegisterSerializer, VerifyPasswordSerializer

logger = logging.getLogger(__name__)
User = get_user_model()


class RegisterView(CreateAPIView):
    """Public endpoint to register a new user"""
    serializer_class = RegisterSerializer
    permission_classes = [AllowAny]


class LogoutView(APIView):
    """Invalidate a refresh token"""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        refresh_token = request.data.get("refresh")
        if not refresh_token:
            return Response(
                {"success": False, "detail": "refresh token required"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            token = RefreshToken(refresh_token)
            token.blacklist()
            return Response(
                {"success": True, "detail": "logout successful"},
                status=status.HTTP_205_RESET_CONTENT,
            )
        except TokenError:
            return Response(
                {"success": False, "detail": "invalid token"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Exception as e:
            logger.exception("LogoutView unexpected error: %s", e)
            return Response(
                {"success": False, "detail": "invalid token"},
                status=status.HTTP_400_BAD_REQUEST,
            )


class PasswordResetRequestView(APIView):
    """Send password reset email if account exists"""
    permission_classes = [AllowAny]

    def post(self, request):
        email = request.data.get("email")
        if not email:
            return Response(
                {"success": False, "detail": "email required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        form = PasswordResetForm(data={"email": email})
        if form.is_valid():
            try:
                form.save(
                    subject_template_name="registration/password_reset_subject.txt",
                    email_template_name="registration/password_reset_email.html",
                    use_https=request.is_secure(),
                    from_email=None,
                    request=request,
                )
            except Exception:
                # Ignore reverse errors if password_reset_confirm isn't configured
                logger.exception("PasswordResetForm.save failed")

        return Response(
            {
                "success": True,
                "detail": "If that email exists, a reset link has been sent.",
            },
            status=status.HTTP_200_OK,
        )


class VerifyPasswordThrottle(SimpleRateThrottle):
    """
    Throttle specifically for verify-password attempts.
    Hard-coded rate to avoid changing settings.py. Adjust "rate" as needed.
    """
    scope = "verify_password"
    rate = "5/min"

    def get_cache_key(self, request, view):
        # throttle per authenticated user; fallback to IP
        if request.user and request.user.is_authenticated:
            ident = getattr(request.user, "pk", None)
            if ident is None:
                return None
            return f"verify-password-user-{ident}"
        return self.get_ident(request)


class VerifyPasswordView(APIView):
    """
    POST /api/v1/auth/verify-password/
    Body: {"password": "<plain>"}
    Requires authentication (token/session). Returns 200 + {"verified": true/false}.
    Logs attempts without recording the password. Throttled to mitigate brute force.
    """
    permission_classes = [IsAuthenticated]
    throttle_classes = [VerifyPasswordThrottle]

    def post(self, request, *args, **kwargs):
        serializer = VerifyPasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        password = serializer.validated_data["password"]

        user = request.user
        try:
            verified = user.check_password(password)
            # Minimal audit log without exposing sensitive data
            logger.info(
                "verify-password attempt user_id=%s verified=%s ip=%s",
                getattr(user, "pk", None),
                bool(verified),
                request.META.get("REMOTE_ADDR"),
            )
            return Response({"verified": bool(verified)}, status=status.HTTP_200_OK)
        except Exception as e:
            logger.exception("verify-password error for user=%s: %s", getattr(user, "pk", None), e)
            return Response(
                {"detail": "internal error"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )