from django.contrib.auth.forms import PasswordResetForm
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.generics import CreateAPIView
from rest_framework_simplejwt.tokens import RefreshToken
import pyotp
import qrcode
import io
import base64

from .serializers import RegisterSerializer

User = get_user_model()


class RegisterView(CreateAPIView):
    serializer_class = RegisterSerializer
    permission_classes = [AllowAny]


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        refresh_token = request.data.get("refresh")
        if not refresh_token:
            return Response({"detail": "refresh token required"}, status=status.HTTP_400_BAD_REQUEST)
        try:
            token = RefreshToken(refresh_token)
            token.blacklist()
            return Response(status=status.HTTP_205_RESET_CONTENT)
        except Exception:
            return Response({"detail": "invalid token"}, status=status.HTTP_400_BAD_REQUEST)


class PasswordResetRequestView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        email = request.data.get("email")
        if not email:
            return Response({"detail": "email required"}, status=status.HTTP_400_BAD_REQUEST)

        form = PasswordResetForm(data={"email": email})
        if form.is_valid():
            form.save(
                subject_template_name="registration/password_reset_subject.txt",
                email_template_name="registration/password_reset_email.html",
                use_https=False,
                from_email=None,
                request=request,
            )
        return Response({"detail": "If that email exists, a reset link has been sent."}, status=status.HTTP_200_OK)


class MFASetupView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        if not getattr(user, "totp_secret", None):
            user.totp_secret = pyotp.random_base32()
            user.save()
            print(f"[DEBUG] Nouveau secret généré pour {user.email}: {user.totp_secret}")
        else:
            print(f"[DEBUG] Secret existant pour {user.email}: {user.totp_secret}")

        totp = pyotp.TOTP(user.totp_secret)
        provisioning_uri = totp.provisioning_uri(name=user.email, issuer_name="BotaApp")
        print(f"[DEBUG] Provisioning URI: {provisioning_uri}")

        import qrcode, io, base64
        qr = qrcode.make(provisioning_uri)
        buffer = io.BytesIO()
        qr.save(buffer, format="PNG")
        qr_base64 = base64.b64encode(buffer.getvalue()).decode()

        print(f"[DEBUG] Longueur du QR base64: {len(qr_base64)}")

        return Response({
            "provisioning_uri": provisioning_uri,
            "qr_base64": qr_base64
        })


class MFAVerifyView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        otp = request.data.get("otp")
        if not otp:
            return Response({"detail": "OTP required"}, status=status.HTTP_400_BAD_REQUEST)
        if not getattr(user, "totp_secret", None):
            return Response({"detail": "MFA not setup"}, status=status.HTTP_400_BAD_REQUEST)

        totp = pyotp.TOTP(user.totp_secret)
        if totp.verify(otp):
            user.is_mfa_enabled = True
            user.is_mfa_verified = True
            user.save()
            return Response({"success": True, "role": getattr(user, "role", None)}, status=status.HTTP_200_OK)
        return Response({"success": False, "error": "Invalid OTP"}, status=status.HTTP_400_BAD_REQUEST)