# bank_accounts/serializers.py
from typing import Any, Dict, Optional
from rest_framework import serializers
from .models import BankAccount, BankTransaction
from manage_personnel.models import Profile


class BankTransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = BankTransaction
        fields = [
            "id",
            "bank_account",
            "profile",
            "type",
            "amount",
            "currency",
            "description",
            "external_reference",
            "timestamp",
            "balance_after",
            "meta",
            "created_at",
        ]
        read_only_fields = ["id", "created_at"]


class BankAccountListSerializer(serializers.ModelSerializer):
    class Meta:
        model = BankAccount
        fields = [
            "id",
            "label",
            "bank_name",
            "bank_code",
            "agency",
            "currency",
            "masked_account",
            "iban_normalized",
            "status",
            "is_primary",
            "verified_at",
            "created_at",
            "updated_at",
        ]


class BankAccountDetailSerializer(serializers.ModelSerializer):
    iban = serializers.SerializerMethodField()
    account_number = serializers.SerializerMethodField()

    class Meta:
        model = BankAccount
        fields = [
            "id",
            "label",
            "bank_name",
            "bank_code",
            "agency",
            "currency",
            "masked_account",
            "iban_normalized",
            "iban",
            "account_number",
            "status",
            "verification_metadata",
            "verified_at",
            "is_primary",
            "created_at",
            "updated_at",
        ]
        read_only_fields = fields

    def _is_owner_or_staff(self) -> bool:
        request = self.context.get("request")
        if not request or not getattr(request, "user", None):
            return False
        user = request.user
        try:
            profile_user_id = getattr(self.instance.profile, "user_id", None) or (
                getattr(self.instance.profile, "user", None) and getattr(self.instance.profile.user, "id", None)
            )
        except Exception:
            profile_user_id = None
        return bool(user.is_staff or (profile_user_id is not None and profile_user_id == getattr(user, "id", None)))

    def get_iban(self, obj: BankAccount) -> Optional[str]:
        return obj.iban_encrypted if self._is_owner_or_staff() else None

    def get_account_number(self, obj: BankAccount) -> Optional[str]:
        return obj.account_number_encrypted if self._is_owner_or_staff() else None


class BankAccountCreateUpdateSerializer(serializers.ModelSerializer):
    iban = serializers.CharField(required=False, allow_blank=True, write_only=True)
    account_number = serializers.CharField(required=False, allow_blank=True, write_only=True)
    profile = serializers.PrimaryKeyRelatedField(queryset=Profile.objects.all(), required=False)

    class Meta:
        model = BankAccount
        fields = [
            "id",
            "label",
            "bank_name",
            "bank_code",
            "agency",
            "currency",
            "iban",
            "account_number",
            "is_primary",
            "status",
            "verification_metadata",
            "profile",
        ]
        read_only_fields = ["id"]

    def validate(self, attrs: Dict[str, Any]) -> Dict[str, Any]:
        # Basic sanity: require either iban or account_number for creation in many flows.
        # But leave flexible for admin workflows.
        return attrs

    def create(self, validated_data: Dict[str, Any]) -> BankAccount:
        iban = validated_data.pop("iban", None)
        account_number = validated_data.pop("account_number", None)
        profile = validated_data.pop("profile", None)
        instance = BankAccount.objects.create(profile=profile, **validated_data)
        if iban:
            instance.set_iban(iban)
        if account_number:
            instance.account_number_encrypted = account_number
            instance.masked_account = instance._mask_iban(account_number)
        instance.save()
        return instance

    def update(self, instance: BankAccount, validated_data: Dict[str, Any]) -> BankAccount:
        iban = validated_data.pop("iban", None)
        account_number = validated_data.pop("account_number", None)
        for k, v in validated_data.items():
            setattr(instance, k, v)
        if iban is not None:
            instance.set_iban(iban)
        if account_number is not None:
            instance.account_number_encrypted = account_number
            instance.masked_account = instance._mask_iban(account_number)
        instance.save()
        return instance