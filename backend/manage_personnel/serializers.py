from rest_framework import serializers
from .models import Profile, Personnel, BankAccount, User


class UserSerializer(serializers.ModelSerializer):
    """Permet de lire / modifier quelques champs de l'utilisateur."""

    class Meta:
        model = User
        fields = [
            "id",
            "email",
            "phone_number",
            "is_mfa_enabled",
            "preferred_2fa",
        ]
        read_only_fields = ["id"]


class ProfileSerializer(serializers.ModelSerializer):
    """
    Sérialiseur du profil.
    - expose `role` et `mfa_enabled` calculés
    - accepte un sous-objet `user` pour mettre à jour certains champs utilisateur
    - gère le champ photo si présent
    - attache automatiquement request.user si présent dans le contexte
    """

    role = serializers.SerializerMethodField(read_only=True)
    mfa_enabled = serializers.SerializerMethodField(read_only=True)
    user = UserSerializer(required=False, allow_null=True)
    date_naissance = serializers.DateField(
        required=False,
        allow_null=True,
        input_formats=["%Y-%m-%d", "%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%S"],
    )

    class Meta:
        model = Profile
        fields = "__all__"
        read_only_fields = ("id", "created_at")

    def get_role(self, obj):
        user = getattr(obj, "user", None)
        return "admin" if (user and user.is_superuser) else "user"

    def get_mfa_enabled(self, obj):
        user = getattr(obj, "user", None)
        return bool(getattr(user, "is_mfa_enabled", False))

    def create(self, validated_data):
        """
        Create a Profile. If request.user is authenticated, attach or update that user's profile.
        Nested 'user' data will update the existing user but will not create a new User.
        """
        user_data = validated_data.pop("user", None)
        request = self.context.get("request", None)

        if request and getattr(request, "user", None) and request.user.is_authenticated:
            user = request.user
            existing = Profile.objects.filter(user=user).first()
            if existing:
                for attr, val in validated_data.items():
                    setattr(existing, attr, val)
                existing.save()
                if user_data:
                    for k, v in user_data.items():
                        if k == "id":
                            continue
                        setattr(user, k, v)
                    user.save()
                return existing

            instance = Profile.objects.create(user=user, **validated_data)
            if user_data:
                for k, v in user_data.items():
                    if k == "id":
                        continue
                    setattr(user, k, v)
                user.save()
            return instance

        # No authenticated user in context: allow creation without linking user
        return Profile.objects.create(**validated_data)

    def update(self, instance, validated_data):
        """
        Update profile fields and optionally nested user fields.
        """
        user_data = validated_data.pop("user", None)

        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()

        if user_data and instance.user:
            for attr, value in user_data.items():
                if attr == "id":
                    continue
                setattr(instance.user, attr, value)
            instance.user.save()

        return instance

    def to_representation(self, instance):
        rep = super().to_representation(instance)
        for key, value in list(rep.items()):
            if value == "":
                rep[key] = None
        return rep


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