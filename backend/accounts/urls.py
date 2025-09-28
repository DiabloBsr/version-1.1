from django.urls import path
from .views import RegisterView, LogoutView, PasswordResetRequestView, MFASetupView, MFAVerifyView

app_name = "accounts"

urlpatterns = [
    path("register/", RegisterView.as_view(), name="register"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("password_reset/", PasswordResetRequestView.as_view(), name="password_reset"),

    # MFA endpoints
    path("mfa/setup/", MFASetupView.as_view(), name="mfa_setup"),
    path("mfa/verify/", MFAVerifyView.as_view(), name="mfa_verify"),
]