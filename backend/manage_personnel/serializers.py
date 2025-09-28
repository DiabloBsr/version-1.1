from rest_framework import serializers
from .models import Profile, Personnel, BankAccount

class ProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = Profile
        fields = "__all__"


class PersonnelSerializer(serializers.ModelSerializer):
    class Meta:
        model = Personnel
        fields = "__all__"


class BankAccountSerializer(serializers.ModelSerializer):
    masked_account = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = BankAccount
        fields = [
            "id",
            "profile",
            "bank_name",
            "bank_code",
            "organisme_code",
            "agency",
            "account_number",
            "rib_key",
            "bk_code",
            "is_primary",
            "masked_account",
        ]
        extra_kwargs = {
            "account_number": {"write_only": False},
            "rib_key": {"required": False, "allow_blank": True},
            "bk_code": {"required": False, "allow_blank": True},
        }

    def get_masked_account(self, obj):
        acct = getattr(obj, "account_number", None)
        if not acct:
            return None
        acct = str(acct)
        if len(acct) <= 4:
            return "••••" + acct
        return "••••" + acct[-4:]

    def validate_account_number(self, value):
        if value is None or str(value).strip() == "":
            raise serializers.ValidationError("Le numéro de compte est requis.")
        s = str(value).strip()
        if not s.isdigit():
            raise serializers.ValidationError("Le numéro de compte doit contenir uniquement des chiffres.")
        if len(s) < 8:
            raise serializers.ValidationError("Le numéro de compte est trop court.")
        return s