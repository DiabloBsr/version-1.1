# bank_accounts/serializers.py
from typing import Any, Dict, Optional
from django.db import transaction
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
        read_only_fields = tuple(fields)

    def _is_owner_or_staff(self) -> bool:
        request = self.context.get("request")
        if not request or not getattr(request, "user", None):
            return False
        user = request.user
        # try to resolve profile user id defensively
        try:
            profile_obj = getattr(self.instance, "profile", None)
            profile_user_id = None
            if profile_obj is not None:
                profile_user_id = getattr(profile_obj, "user_id", None) or (
                    getattr(profile_obj, "user", None) and getattr(profile_obj.user, "id", None)
                )
        except Exception:
            profile_user_id = None
        return bool(user.is_staff or (profile_user_id is not None and profile_user_id == getattr(user, "id", None)))

    def get_iban(self, obj: BankAccount) -> Optional[str]:
        if not obj:
            return None
        return obj.iban_encrypted if self._is_owner_or_staff() else None

    def get_account_number(self, obj: BankAccount) -> Optional[str]:
        if not obj:
            return None
        return obj.account_number_encrypted if self._is_owner_or_staff() else None


class BankAccountCreateUpdateSerializer(serializers.ModelSerializer):
    iban = serializers.CharField(required=False, allow_blank=True, write_only=True)
    account_number = serializers.CharField(required=False, allow_blank=True, write_only=True)
    profile = serializers.PrimaryKeyRelatedField(queryset=Profile.objects.all(), required=False, allow_null=True)

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
        # Keep flexible: no hard requirement here, but strip blanks to None
        if "iban" in attrs and isinstance(attrs["iban"], str) and attrs["iban"].strip() == "":
            attrs.pop("iban")
        if "account_number" in attrs and isinstance(attrs["account_number"], str) and attrs["account_number"].strip() == "":
            attrs.pop("account_number")
        return attrs

    def _resolve_profile(self) -> Optional[Profile]:
        # Prefer explicit profile in payload, otherwise try request.user -> profile
        request = self.context.get("request")
        payload_profile = self.initial_data.get("profile")
        if payload_profile:
            try:
                return Profile.objects.get(pk=payload_profile)
            except Exception:
                return None
        if request and getattr(request, "user", None):
            # attempt common relation names
            user = request.user
            try:
                return getattr(user, "profile", None) or Profile.objects.filter(user_id=getattr(user, "id", None)).first()
            except Exception:
                return None
        return None

    @transaction.atomic
    def create(self, validated_data: Dict[str, Any]) -> BankAccount:
        iban = validated_data.pop("iban", None)
        account_number = validated_data.pop("account_number", None)
        profile = validated_data.pop("profile", None) or self._resolve_profile()
        # profile may be None; if your flows require a profile enforce it here
        instance = BankAccount.objects.create(profile=profile, **validated_data)
        if iban:
            instance.set_iban(iban)
        if account_number:
            instance.account_number_encrypted = account_number
            instance.masked_account = instance._mask_iban(account_number)
        instance.save()
        return instance

    @transaction.atomic
    def update(self, instance: BankAccount, validated_data: Dict[str, Any]) -> BankAccount:
        iban = validated_data.pop("iban", None)
        account_number = validated_data.pop("account_number", None)
        profile = validated_data.pop("profile", None)
        if profile is not None:
            instance.profile = profile
        for k, v in validated_data.items():
            setattr(instance, k, v)
        if iban is not None:
            instance.set_iban(iban)
        if account_number is not None:
            instance.account_number_encrypted = account_number
            instance.masked_account = instance._mask_iban(account_number)
        instance.save()
        return instance