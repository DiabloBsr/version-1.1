from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.utils.timezone import now
from django.db.models import Count
from manage_personnel.models import User, Profile, Personnel


class DashboardSummaryView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        today = now().date()
        start_month = today.replace(day=1)

        total_users = User.objects.count()
        active_personnel = Personnel.objects.count()
        new_this_month = Personnel.objects.filter(profile__created_at__gte=start_month).count()

        # Répartition par âge (nouvelles tranches)
        age_distribution = {
            "20_30": 0,
            "31_40": 0,
            "41_50": 0,
            "51_55": 0,
            "56_60": 0,
            "61_plus": 0,
        }

        for profile in Profile.objects.exclude(date_naissance__isnull=True):
            age = profile.age
            if age is None:
                continue

            if 20 <= age <= 30:
                age_distribution["20_30"] += 1
            elif 31 <= age <= 40:
                age_distribution["31_40"] += 1
            elif 41 <= age <= 50:
                age_distribution["41_50"] += 1
            elif 51 <= age <= 55:
                age_distribution["51_55"] += 1
            elif 56 <= age <= 60:
                age_distribution["56_60"] += 1
            elif age >= 61:
                age_distribution["61_plus"] += 1

        # Situation matrimoniale
        marital_status_qs = (
            Profile.objects.values("situation_matrimoniale").annotate(count=Count("id"))
        )
        marital_map = {
            entry["situation_matrimoniale"] or "Non spécifiée": entry["count"]
            for entry in marital_status_qs
        }

        # Spécialités
        specialty_qs = Personnel.objects.values("specialite").annotate(count=Count("id"))
        specialty_map = {
            entry["specialite"] or "Non spécifiée": entry["count"]
            for entry in specialty_qs
        }

        # Derniers arrivés
        recent_personnel_qs = (
            Personnel.objects.select_related("profile")
            .order_by("-profile__created_at")[:5]
        )
        recent_personnel = [
            {
                "name": f"{p.profile.nom or ''} {p.profile.prenom or ''}".strip(),
                "role": p.specialite or "Non spécifiée",
                "joined": p.profile.created_at.date() if p.profile.created_at else None,
            }
            for p in recent_personnel_qs
        ]

        # Anniversaires proches
        upcoming_birthdays = []
        for p in Profile.objects.exclude(date_naissance__isnull=True):
            if p.anniversaire_est_proche():
                upcoming_birthdays.append(
                    {
                        "name": f"{p.nom or ''} {p.prenom or ''}".strip(),
                        "date": p.date_naissance.strftime("%d/%m"),
                        "email": p.email or "",
                    }
                )

        return Response(
            {
                "total_users": total_users,
                "active_personnel": active_personnel,
                "new_this_month": new_this_month,
                "age_distribution": age_distribution,
                "marital_status": marital_map,
                "by_specialty": specialty_map,
                "recent_personnel": recent_personnel,
                "upcoming_birthdays": upcoming_birthdays,
            }
        )