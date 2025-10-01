from rest_framework import viewsets, status, mixins, serializers
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.pagination import PageNumberPagination
from rest_framework.filters import OrderingFilter, SearchFilter
from rest_framework.decorators import action
from django_filters.rest_framework import DjangoFilterBackend
from django.db import transaction

from .models import Activity
from .serializers import ActivitySerializer


class StandardResultsSetPagination(PageNumberPagination):
    page_size = 50
    page_size_query_param = "limit"
    max_page_size = 200


class ActivityBatchSerializer(serializers.Serializer):
    activities = serializers.ListField(child=serializers.DictField(), allow_empty=False)


class ActivityViewSet(mixins.ListModelMixin,
                      mixins.CreateModelMixin,
                      viewsets.GenericViewSet):
    """
    ViewSet for Activity

    - List: returns activities for the authenticated user, paginated.
    - Create: creates an activity for request.user; serializer enforces ownership
      and attempts de-duplication when external_id is provided.
    - batch: accepts multiple activities and returns per-item results.
    """

    serializer_class = ActivitySerializer
    permission_classes = [IsAuthenticated]
    pagination_class = StandardResultsSetPagination
    filter_backends = [DjangoFilterBackend, OrderingFilter, SearchFilter]
    filterset_fields = ["type", "external_id", "visible"]
    search_fields = ["text"]  # avoid JSONField search issues by excluding 'meta'
    ordering_fields = ["timestamp", "created_at"]
    ordering = ["-timestamp", "-created_at"]

    def get_queryset(self):
        # restrict to the requesting user's activities
        user = self.request.user
        return Activity.objects.filter(user=user).order_by("-timestamp", "-created_at")

    @transaction.atomic
    def create(self, request, *args, **kwargs):
        # Use serializer.create to enforce user and dedup behavior
        serializer = self.get_serializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        instance = serializer.save()
        out_serializer = self.get_serializer(instance)
        headers = self.get_success_headers(out_serializer.data)
        response = Response(out_serializer.data, status=status.HTTP_201_CREATED, headers=headers)
        # Ensure charset present so clients decode UTF-8 correctly
        response.headers['Content-Type'] = 'application/json; charset=utf-8'
        return response

    @action(detail=False, methods=["post"], url_path="batch")
    @transaction.atomic
    def batch(self, request, *args, **kwargs):
        """
        Batch create/update activities.

        Expected payload:
        {
          "activities": [
            { "text": "...", "type": "...", "timestamp": "...", "meta": {...}, "external_id": "..." },
            ...
          ]
        }

        Response:
        {
          "results": [
            { "index": 0, "status": "ok", "id": 12, "external_id": "..." },
            { "index": 1, "status": "error", "error": {"text": ["This field is required."]} }
          ]
        }
        """
        serializer = ActivityBatchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        raw_list = serializer.validated_data["activities"]

        results = []
        for idx, item in enumerate(raw_list):
            item_serializer = ActivitySerializer(data=item, context={"request": request})
            if not item_serializer.is_valid():
                results.append({"index": idx, "status": "error", "error": item_serializer.errors})
                continue
            try:
                instance = item_serializer.save()
                results.append({
                    "index": idx,
                    "status": "ok",
                    "id": instance.id,
                    "external_id": instance.external_id
                })
            except Exception as exc:
                results.append({"index": idx, "status": "error", "error": str(exc)})

        response = Response({"results": results}, status=status.HTTP_200_OK)
        # Ensure charset present so clients decode UTF-8 correctly
        response.headers['Content-Type'] = 'application/json; charset=utf-8'
        return response