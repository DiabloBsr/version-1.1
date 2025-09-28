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

        # Répartition par âge
        age_distribution = {"18_25": 0, "26_35": 0, "36_50": 0, "51_plus": 0}
        for profile in Profile.objects.all():
            age = profile.age
            if 18 <= age <= 25:
                age_distribution["18_25"] += 1
            elif 26 <= age <= 35:
                age_distribution["26_35"] += 1
            elif 36 <= age <= 50:
                age_distribution["36_50"] += 1
            elif age > 50:
                age_distribution["51_plus"] += 1

        # Situation matrimoniale
        marital_status_qs = Profile.objects.values('situation_matrimoniale').annotate(count=Count('id'))
        marital_map = {entry['situation_matrimoniale']: entry['count'] for entry in marital_status_qs}

        # Spécialités
        specialty_qs = Personnel.objects.values('specialite').annotate(count=Count('id'))
        specialty_map = {entry['specialite'] or "Non spécifiée": entry['count'] for entry in specialty_qs}

        # Derniers arrivés
        recent_personnel_qs = Personnel.objects.select_related('profile').order_by('-profile__created_at')[:5]
        recent_personnel = [
            {
                "name": f"{p.profile.nom} {p.profile.prenom}",
                "role": p.specialite or "Non spécifiée",
                "joined": p.profile.created_at.date(),
            }
            for p in recent_personnel_qs
        ]

        # Anniversaires proches
        upcoming_birthdays = [
            {
                "name": f"{p.nom} {p.prenom}",
                "date": p.date_naissance.strftime("%d/%m"),
                "email": p.email,
            }
            for p in Profile.objects.all() if p.anniversaire_est_proche()
        ]

        return Response({
            "total_users": total_users,
            "active_personnel": active_personnel,
            "new_this_month": new_this_month,
            "age_distribution": age_distribution,
            "marital_status": marital_map,
            "by_specialty": specialty_map,
            "recent_personnel": recent_personnel,
            "upcoming_birthdays": upcoming_birthdays,
        })