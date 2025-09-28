from django.contrib import admin
from django.urls import path, include
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path("admin/", admin.site.urls),

    # API de gestion du personnel
    path(
        "api/v1/",
        include(("manage_personnel.urls", "manage_personnel"), namespace="manage_personnel")
    ),

    # Authentification (custom + Djoser)
    path("api/v1/auth/", include(("accounts.urls", "accounts"), namespace="accounts")),
    path("api/v1/auth/", include("djoser.urls")),
    path("api/v1/auth/", include("djoser.urls.jwt")),

    # JWT tokens (optionnel si tu veux garder des endpoints simples en plus de Djoser)
    path("api/v1/token/", TokenObtainPairView.as_view(), name="token_obtain_pair"),
    path("api/v1/token/refresh/", TokenRefreshView.as_view(), name="token_refresh"),

    # Tableau de bord RH
    path("api/v1/dashboard/", include("dashboard.urls")),
]

# Serve media files in development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)