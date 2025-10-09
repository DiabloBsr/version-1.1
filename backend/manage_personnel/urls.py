# manage_personnel/urls.py
from rest_framework.routers import DefaultRouter
from django.urls import path, include
from .views import ProfileViewSet, PersonnelViewSet, UserExistsView

router = DefaultRouter()
router.register(r"profiles", ProfileViewSet, basename="profile")
router.register(r"personnel", PersonnelViewSet, basename="personnel")

urlpatterns = [
    path("", include(router.urls)),
    path("users/exists", UserExistsView.as_view(), name="user-exists"),
]