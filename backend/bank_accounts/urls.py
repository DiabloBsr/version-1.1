# bank_accounts/urls.py
from rest_framework.routers import DefaultRouter
from .views import BankAccountViewSet

router = DefaultRouter()
router.register(r"bank-accounts", BankAccountViewSet, basename="bankaccount")

urlpatterns = router.urls