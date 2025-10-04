# bank_accounts/urls.py
from rest_framework.routers import DefaultRouter
from django.urls import path, include

from .views import BankAccountViewSet, BankTransactionViewSet

router = DefaultRouter()
router.register(r'bank-accounts', BankAccountViewSet, basename='bankaccount')
router.register(r'bank-transactions', BankTransactionViewSet, basename='banktransaction')

urlpatterns = [
    path('', include(router.urls)),
]