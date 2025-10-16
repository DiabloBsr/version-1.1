# accounts/urls.py
from django.urls import path
from .views import (
    RegisterView,
    LogoutView,
    PasswordResetRequestView,
    VerifyPasswordView,
)

app_name = "accounts"

urlpatterns = [
    path("register/", RegisterView.as_view(), name="register"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("password_reset/", PasswordResetRequestView.as_view(), name="password_reset"),
    path("verify-password/", VerifyPasswordView.as_view(), name="verify-password"),
]