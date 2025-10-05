# bank_accounts/serializers.py
from rest_framework import serializers
from rest_framework.request import Request
from .models import BankAccount, BankTransaction


class BankAccountCreateSerializer(serializers.ModelSerializer):
    iban = serializers.CharField(write_only=True, required=False, allow_blank=True)
    account_number = serializers.CharField(write_only=True, required=False, allow_blank=True)
    masked_account = serializers.CharField(read_only=True)

    class Meta:
        model = BankAccount
        fields = [
            "id", "profile", "label", "bank_name", "bank_code", "agency", "currency",
            "iban", "account_number", "masked_account", "is_primary",
        ]
        read_only_fields = ["id", "masked_account"]

    def validate(self, attrs):
        if not attrs.get("iban") and not attrs.get("account_number"):
            raise serializers.ValidationError("Either iban or account_number must be provided.")
        return attrs

    def create(self, validated_data):
        iban = validated_data.pop("iban", None)
        acct = validated_data.pop("account_number", None)
        instance = BankAccount(**validated_data)
        if iban:
            instance.set_iban(iban)
        if acct:
            instance.account_number_encrypted = acct
            # masked_account will be recomputed in save()
            if not instance.masked_account:
                instance.masked_account = acct
        if instance.is_primary:
            BankAccount.objects.filter(profile=instance.profile, is_primary=True).update(is_primary=False)
        instance.save()
        return instance


class BankAccountUpdateSerializer(serializers.ModelSerializer):
    """
    Serializer used for update/partial_update.
    Accepts write-only fields for iban/account_number and applies them in the view's perform_update.
    """
    iban = serializers.CharField(write_only=True, required=False, allow_blank=True)
    account_number = serializers.CharField(write_only=True, required=False, allow_blank=True)
    masked_account = serializers.CharField(read_only=True)

    class Meta:
        model = BankAccount
        fields = [
            "id", "profile", "label", "bank_name", "bank_code", "agency", "currency",
            "iban", "account_number", "masked_account", "is_primary", "status",
        ]
        read_only_fields = ["id", "masked_account", "profile"]


class BankAccountDetailSerializer(serializers.ModelSerializer):
    iban = serializers.SerializerMethodField()
    account_number = serializers.SerializerMethodField()

    class Meta:
        model = BankAccount
        fields = [
            "id", "profile", "label", "bank_name", "bank_code", "agency", "currency",
            "iban", "account_number", "masked_account", "is_primary", "status", "created_at", "updated_at",
        ]
        read_only_fields = fields

    def _is_owner_or_staff(self, request: Request, obj: BankAccount) -> bool:
        if not request or not getattr(request, "user", None) or not request.user.is_authenticated:
            return False
        if request.user.is_staff:
            return True
        profile = getattr(obj, "profile", None)
        if profile is None:
            return False
        return getattr(profile, "user_id", None) == getattr(request.user, "id", None) or getattr(profile, "user", None) == request.user

    def get_iban(self, obj: BankAccount):
        request = self.context.get("request")
        return obj.iban_encrypted if self._is_owner_or_staff(request, obj) else None

    def get_account_number(self, obj: BankAccount):
        request = self.context.get("request")
        return obj.account_number_encrypted if self._is_owner_or_staff(request, obj) else None


class BankTransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = BankTransaction
        fields = "__all__"
        read_only_fields = ["id", "created_at"]