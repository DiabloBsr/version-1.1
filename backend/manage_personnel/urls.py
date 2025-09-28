from rest_framework.routers import DefaultRouter
from .views import ProfileViewSet, PersonnelViewSet, BankAccountViewSet

app_name = "manage_personnel"

router = DefaultRouter()
router.register(r"profiles", ProfileViewSet, basename="profile")
router.register(r"personnel", PersonnelViewSet, basename="personnel")
router.register(r"bank-accounts", BankAccountViewSet, basename="bankaccount")

urlpatterns = router.urls