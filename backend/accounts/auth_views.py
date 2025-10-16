# accounts/auth_views.py
from django.contrib.auth.forms import PasswordResetForm
from django.contrib.auth import get_user_model
from django.core.exceptions import ImproperlyConfigured
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.generics import CreateAPIView
from rest_framework_simplejwt.tokens import RefreshToken, TokenError

from .serializers import RegisterSerializer

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
            try:
                token.blacklist()
            except AttributeError:
                raise ImproperlyConfigured(
                    "rest_framework_simplejwt.token_blacklist is not available. "
                    "Add it to INSTALLED_APPS and run migrations."
                )
            return Response(
                {"success": True, "detail": "logout successful"},
                status=status.HTTP_205_RESET_CONTENT,
            )
        except TokenError:
            return Response(
                {"success": False, "detail": "invalid token"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        except ImproperlyConfigured as e:
            return Response(
                {"success": False, "detail": str(e)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        except Exception:
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
                # Prevent crash if password_reset_confirm is not configured
                pass

        return Response(
            {
                "success": True,
                "detail": "If that email exists, a reset link has been sent.",
            },
            status=status.HTTP_200_OK,
        )