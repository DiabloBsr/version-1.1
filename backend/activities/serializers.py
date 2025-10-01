from rest_framework import serializers
from django.utils import timezone
from .models import Activity


class ActivitySerializer(serializers.ModelSerializer):
    """
    Serializer for Activity model.

    - On create, the user is taken from serializer context (request.user) and not from the payload.
    - If the client provides external_id, the view may use this to deduplicate; serializer
      will accept it but will not change ownership.
    - timestamp may be provided by the client; otherwise server will use now().
    """

    user = serializers.PrimaryKeyRelatedField(read_only=True)
    created_at = serializers.DateTimeField(read_only=True)
    timestamp = serializers.DateTimeField(required=False, allow_null=True)
    meta = serializers.JSONField(required=False, allow_null=True)

    class Meta:
        model = Activity
        fields = [
            "id",
            "user",
            "text",
            "type",
            "meta",
            "timestamp",
            "created_at",
            "external_id",
            "visible",
        ]
        read_only_fields = ["id", "user", "created_at"]

    def validate_text(self, value):
        if not value or not str(value).strip():
            raise serializers.ValidationError("Le champ text ne peut pas être vide.")
        return value

    def validate_type(self, value):
        # Optional: restrict to known choices. For now accept any non-empty string or null.
        if value is None:
            return value
        v = str(value).strip()
        if v == "":
            return None
        return v

    def to_internal_value(self, data):
        # Let DRF handle standard conversions; ensure timestamp fallback is handled in create.
        return super().to_internal_value(data)

    def create(self, validated_data):
        request = self.context.get("request", None)
        user = getattr(request, "user", None)
        if user is None or user.is_anonymous:
            raise serializers.ValidationError("Utilisateur non authentifié.")

        # Ensure timestamp exists
        if not validated_data.get("timestamp"):
            validated_data["timestamp"] = timezone.now()

        # Do not allow client to set 'user' via payload; enforce request.user
        validated_data["user"] = user

        # If external_id is provided, do not silently create duplicates.
        external_id = validated_data.get("external_id", None)
        if external_id:
            # Try to find existing activity with same external_id for this user
            existing = Activity.objects.filter(user=user, external_id=external_id).order_by("-created_at").first()
            if existing:
                # Option: update text/meta/timestamp if incoming data differs (light merge)
                # We'll update the existing record and return it rather than creating a duplicate.
                existing.text = validated_data.get("text", existing.text)
                existing.type = validated_data.get("type", existing.type)
                existing.meta = validated_data.get("meta", existing.meta)
                existing.timestamp = validated_data.get("timestamp", existing.timestamp)
                existing.visible = validated_data.get("visible", existing.visible)
                existing.save(update_fields=["text", "type", "meta", "timestamp", "visible"])
                return existing

        return super().create(validated_data)