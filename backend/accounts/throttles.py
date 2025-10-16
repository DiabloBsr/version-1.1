# accounts/throttles.py
from rest_framework.throttling import SimpleRateThrottle

class VerifyPasswordThrottle(SimpleRateThrottle):
    # explicit rate hard-coded here so settings.py remains untouched
    rate = "5/min"  # ajuster si nécessaire

    def get_cache_key(self, request, view):
        if request.user and request.user.is_authenticated:
            ident = getattr(request.user, "pk", None)
            if ident is None:
                return None
            return f"verify-password-user-{ident}"
        # fallback to IP for anonymous (should not happen since view requires auth)
        return self.get_ident(request)