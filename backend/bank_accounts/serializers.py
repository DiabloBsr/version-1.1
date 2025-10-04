# bank_accounts/serializers.py
from rest_framework import serializers
from django.utils import timezone
from .models import BankAccount, BankTransaction

class BankAccountCreateSerializer(serializers.ModelSerializer):
    """
    Serializer for creating BankAccount. Stores plaintext into encrypted fields
    via model helpers (set_iban or direct assignment).
    """
    iban = serializers.CharField(write_only=True, required=False, allow_blank=True)
    account_number = serializers.CharField(write_only=True, required=False, allow_blank=True)
    masked_account = serializers.CharField(read_only=True)

    class Meta:
        model = BankAccount
        fields = [
            "id",
            "profile",
            "label",
            "bank_name",
            "bank_code",
            "agency",
            "currency",
            "iban",
            "account_number",
            "masked_account",
            "is_primary",
        ]
        read_only_fields = ["id", "masked_account"]

    def validate(self, attrs):
        # minimal validation: require either iban or account_number
        iban = attrs.get("iban")
        acct = attrs.get("account_number")
        if not iban and not acct:
            raise serializers.ValidationError("Either iban or account_number must be provided.")
        return attrs

    def create(self, validated_data):
        iban = validated_data.pop("iban", None)
        acct = validated_data.pop("account_number", None)
        # ensure profile is set (passed as uuid or nested)
        instance = BankAccount(**validated_data)
        if iban:
            instance.set_iban(iban)
        if acct:
            # assign to encrypted field directly; model save will compute masked_account if needed
            instance.account_number_encrypted = acct
            if not instance.masked_account:
                instance.masked_account = acct
        # handle is_primary: if true, unset other primaries for profile
        if instance.is_primary:
            BankAccount.objects.filter(profile=instance.profile, is_primary=True).update(is_primary=False)
        instance.save()
        return instance

class BankAccountDetailSerializer(serializers.ModelSerializer):
    iban = serializers.SerializerMethodField()
    account_number = serializers.SerializerMethodField()

    class Meta:
        model = BankAccount
        fields = [
            "id",
            "profile",
            "label",
            "bank_name",
            "bank_code",
            "agency",
            "currency",
            "iban",
            "account_number",
            "masked_account",
            "is_primary",
            "status",
            "created_at",
            "updated_at",
        ]
        read_only_fields = fields

    def _is_owner_or_staff(self):
        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return False
        # allow staff or owner of profile (profile can be uuid or object)
        if request.user.is_staff:
            return True
        profile = self.instance.profile
        return getattr(profile, "user_id", None) == getattr(request.user, "id", None) or getattr(profile, "user", None) == request.user

    def get_iban(self, obj):
        return obj.iban_encrypted if self._is_owner_or_staff() else None

    def get_account_number(self, obj):
        return obj.account_number_encrypted if self._is_owner_or_staff() else None

class BankTransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = BankTransaction
        fields = "__all__"
        read_only_fields = ["id", "created_at"]