from django.contrib.auth.forms import PasswordResetForm
from django.contrib.auth import get_user_model
from django.core.exceptions import ImproperlyConfigured
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.generics import CreateAPIView
from rest_framework_simplejwt.tokens import RefreshToken, TokenError

import pyotp

from .serializers import RegisterSerializer, TOTPSetupSerializer, TOTPVerifySerializer

User = get_user_model()


class RegisterView(CreateAPIView):
    """
    Public endpoint to register a new user.
    Accepts: { email, password, first_name, last_name }
    """
    serializer_class = RegisterSerializer
    permission_classes = [AllowAny]


class LogoutView(APIView):
    """
    Blacklist the refresh token provided in the request body:
    { "refresh": "<refresh_token>" }

    Requires rest_framework_simplejwt.token_blacklist in INSTALLED_APPS and
    migrations applied. Returns 205 on success, 400 on invalid/missing token.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        refresh_token = request.data.get("refresh")
        if not refresh_token:
            return Response({"detail": "refresh token required"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            token = RefreshToken(refresh_token)
            # token.blacklist() requires the token_blacklist app
            try:
                token.blacklist()
            except AttributeError:
                raise ImproperlyConfigured(
                    "rest_framework_simplejwt.token_blacklist is not available. "
                    "Add it to INSTALLED_APPS and run migrations."
                )
            return Response(status=status.HTTP_205_RESET_CONTENT)
        except TokenError:
            return Response({"detail": "invalid token"}, status=status.HTTP_400_BAD_REQUEST)
        except ImproperlyConfigured as e:
            return Response({"detail": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        except Exception:
            return Response({"detail": "invalid token"}, status=status.HTTP_400_BAD_REQUEST)


class PasswordResetRequestView(APIView):
    """
    Accepts { "email": "<user_email>" } and, if a matching account exists,
    triggers Django's PasswordResetForm.save() which sends the reset email.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        email = request.data.get("email")
        if not email:
            return Response({"detail": "email required"}, status=status.HTTP_400_BAD_REQUEST)

        form = PasswordResetForm(data={"email": email})
        # form.save() is safe: it won't reveal whether the email exists.
        if form.is_valid():
            # configure subject_template_name / email_template_name in templates/registration/
            form.save(
                subject_template_name="registration/password_reset_subject.txt",
                email_template_name="registration/password_reset_email.html",
                use_https=request.is_secure(),
                from_email=None,
                request=request,
            )
        return Response({"detail": "If that email exists, a reset link has been sent."}, status=status.HTTP_200_OK)


class TOTPSetupView(APIView):
    """
    POST creates or returns the user's TOTP secret provisioning URI.
    Response: { "provisioning_uri": "<otpauth://...>" }
    Requires authenticated user.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        # create secret if not exists
        secret = getattr(user, "totp_secret", None)
        if not secret:
            secret = pyotp.random_base32()
            # try to set attribute and save; field must exist on the user model
            try:
                user.totp_secret = secret
                user.save(update_fields=["totp_secret"])
            except Exception:
                return Response({"detail": "unable to persist totp_secret on user model"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        provisioning_uri = pyotp.totp.TOTP(secret).provisioning_uri(name=user.email, issuer_name="Bota")
        # serializer for output (don't call is_valid on serializer used for serialization)
        serializer = TOTPSetupSerializer(data={"provisioning_uri": provisioning_uri})
        serializer.is_valid(raise_exception=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


class TOTPVerifyView(APIView):
    """
    POST verifies an otp against the stored TOTP secret.
    Accepts: { "otp": "123456" }
    On success marks user's is_mfa_verified True (if field exists).
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = TOTPVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        otp = serializer.validated_data["otp"]
        user = request.user
        secret = getattr(user, "totp_secret", None)
        if not secret:
            return Response({"detail": "MFA not setup"}, status=status.HTTP_400_BAD_REQUEST)

        totp = pyotp.TOTP(secret)
        if totp.verify(otp, valid_window=1):
            # set verification flag if present
            if hasattr(user, "is_mfa_verified"):
                try:
                    user.is_mfa_verified = True
                    user.save(update_fields=["is_mfa_verified"])
                except Exception:
                    pass
            return Response({"detail": "verified"}, status=status.HTTP_200_OK)

        return Response({"detail": "invalid otp"}, status=status.HTTP_400_BAD_REQUEST)