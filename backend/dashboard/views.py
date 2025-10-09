# manage_personnel/dashboard/view.py
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.utils.timezone import now
from django.db.models import Count, Q
from datetime import date, datetime, timedelta

from manage_personnel.models import User, Profile, Personnel


class DashboardSummaryView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        today = now().date()
        start_month = today.replace(day=1)
        year = today.year
        month = today.month

        # total users (all User records)
        total_users = User.objects.count()

        # active personnel
        # consider a Personnel "active" when their related User.is_active == True
        active_personnel = Personnel.objects.filter(profile__user__is_active=True).count()

        # new this month: Users created from the 1st of current month up to today (inclusive)
        new_this_month = User.objects.filter(created_at__year=year, created_at__month=month).count()

        # Age distribution buckets
        age_distribution = {
            "20_30": 0,
            "31_40": 0,
            "41_50": 0,
            "51_55": 0,
            "56_60": 0,
            "61_plus": 0,
        }

        profiles_with_bd = Profile.objects.exclude(date_naissance__isnull=True)
        for profile in profiles_with_bd:
            try:
                bd = profile.date_naissance
                if isinstance(bd, datetime):
                    bd = bd.date()
                if not bd:
                    continue
                # compute age
                today_dt = today
                age = today_dt.year - bd.year - ((today_dt.month, today_dt.day) < (bd.month, bd.day))
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
            except Exception:
                continue

        # Situation matrimoniale counts
        marital_status_qs = Profile.objects.values("situation_matrimoniale").annotate(count=Count("id"))
        marital_map = {}
        for entry in marital_status_qs:
            key = entry.get("situation_matrimoniale") or "Non spécifiée"
            marital_map[str(key)] = entry.get("count", 0)

        # Specialties by Personnel
        specialty_qs = Personnel.objects.values("specialite").annotate(count=Count("id"))
        specialty_map = {}
        for entry in specialty_qs:
            key = entry.get("specialite") or "Non spécifiée"
            specialty_map[str(key)] = entry.get("count", 0)

        # Recent personnel: order by profile.created_at desc (most recent first)
        recent_personnel_qs = (
            Personnel.objects.select_related("profile", "profile__user")
            .filter(profile__created_at__isnull=False)
            .order_by("-profile__created_at")[:8]
        )
        recent_personnel = []
        for p in recent_personnel_qs:
            try:
                prof = p.profile
                name = f"{prof.nom or ''} {prof.prenom or ''}".strip() or (prof.user.email if prof.user else "")
                joined_dt = prof.created_at
                joined = joined_dt.isoformat() if joined_dt else None
                recent_personnel.append(
                    {
                        "id": str(prof.id),
                        "name": name,
                        "role": p.specialite or "Non spécifiée",
                        "joined": joined,
                    }
                )
            except Exception:
                continue

        # Upcoming birthdays: next 30 days (robust across year boundary)
        upcoming_birthdays = []
        days_ahead = 30
        end_date = today + timedelta(days=days_ahead)
        candidates = Profile.objects.exclude(date_naissance__isnull=True)
        for p in candidates:
            try:
                bd = p.date_naissance
                if isinstance(bd, datetime):
                    bd = bd.date()
                # next birthday for this profile
                this_year_bday = date(today.year, bd.month, bd.day)
                if this_year_bday < today:
                    next_bday = date(today.year + 1, bd.month, bd.day)
                else:
                    next_bday = this_year_bday
                if today <= next_bday <= end_date:
                    name = f"{p.nom or ''} {p.prenom or ''}".strip()
                    upcoming_birthdays.append(
                        {
                            "id": str(p.id),
                            "name": name,
                            "date": next_bday.isoformat(),
                            "email": p.email or "",
                        }
                    )
            except Exception:
                continue

        upcoming_birthdays = sorted(upcoming_birthdays, key=lambda x: x["date"])[:8]

        payload = {
            "total_users": total_users,
            "active_personnel": active_personnel,
            "new_this_month": new_this_month,
            "age_distribution": age_distribution,
            "marital_status": marital_map,
            "by_specialty": specialty_map,
            "recent_personnel": recent_personnel,
            "upcoming_birthdays": upcoming_birthdays,
        }

        return Response(payload)