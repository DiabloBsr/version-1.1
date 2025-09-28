from django.contrib.auth import get_user_model
from rest_framework import serializers
from rest_framework import serializers

User = get_user_model()


class TOTPSetupSerializer(serializers.Serializer):
    otp = serializers.CharField(write_only=True, required=False)
    provisioning_uri = serializers.CharField(read_only=True)

class TOTPVerifySerializer(serializers.Serializer):
    otp = serializers.CharField(write_only=True)


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ("id", "email", "password", "first_name", "last_name")
        read_only_fields = ("id",)

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return value

    def create(self, validated_data):
        password = validated_data.pop("password")
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user