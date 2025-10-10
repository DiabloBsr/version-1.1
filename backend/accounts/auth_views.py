from django.contrib.auth.forms import PasswordResetForm
from django.contrib.auth import get_user_model
from django.core.exceptions import ImproperlyConfigured
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.generics import CreateAPIView
from rest_framework_simplejwt.tokens import RefreshToken, TokenError

import pyotp, qrcode, io, base64

from .serializers import RegisterSerializer, TOTPVerifySerializer

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
                # Empêche le crash si password_reset_confirm n'est pas configuré
                pass

        return Response(
            {
                "success": True,
                "detail": "If that email exists, a reset link has been sent.",
            },
            status=status.HTTP_200_OK,
        )


class TOTPSetupView(APIView):
    """
    Generate or return TOTP QR code (base64 only).
    Response: { "success": true, "detail": "...", "qr_base64": "data:image/png;base64,..." }
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        secret = getattr(user, "totp_secret", None)
        if not secret:
            secret = pyotp.random_base32()
            try:
                user.totp_secret = secret
                user.save(update_fields=["totp_secret"])
            except Exception:
                return Response(
                    {"success": False, "detail": "unable to persist totp_secret"},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR,
                )

        provisioning_uri = pyotp.TOTP(secret).provisioning_uri(
            name=user.email,
            issuer_name="BotaApp"
        )

        try:
            qr = qrcode.make(provisioning_uri)
            buffer = io.BytesIO()
            qr.save(buffer, format="PNG")
            qr_base64 = base64.b64encode(buffer.getvalue()).decode()
        except Exception as e:
            return Response(
                {"success": False, "detail": f"QR generation failed: {e}"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {
                "success": True,
                "detail": "MFA setup complete",
                "qr_base64": f"data:image/png;base64,{qr_base64}",
            },
            status=status.HTTP_200_OK,
        )


class TOTPVerifyView(APIView):
    """Verify OTP code against stored TOTP secret"""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = TOTPVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        otp = serializer.validated_data["otp"]

        user = request.user
        secret = getattr(user, "totp_secret", None)
        if not secret:
            return Response(
                {"success": False, "detail": "MFA not setup"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        totp = pyotp.TOTP(secret)
        if totp.verify(otp, valid_window=1):
            if hasattr(user, "is_mfa_verified"):
                user.is_mfa_verified = True
                user.save(update_fields=["is_mfa_verified"])
            return Response(
                {"success": True, "detail": "verified"},
                status=status.HTTP_200_OK,
            )

        return Response(
            {"success": False, "detail": "invalid otp"},
            status=status.HTTP_400_BAD_REQUEST,
        )