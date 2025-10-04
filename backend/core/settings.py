"""
Django settings for core project.

Cleaned, consolidated and ready for development.
Adjust secrets and production flags via the .env file.
"""
import json
import os
from pathlib import Path
from datetime import timedelta
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(dotenv_path=BASE_DIR / ".env")

# Basic security / env
SECRET_KEY = os.getenv("SECRET_KEY", "replace-me-for-dev")
DEBUG = os.getenv("DEBUG", "False").lower() in ("1", "true", "yes")
ALLOWED_HOSTS = [h.strip() for h in os.getenv("ALLOWED_HOSTS", "127.0.0.1,localhost").split(",") if h.strip()]

# Application definition
INSTALLED_APPS = [
    # Django contrib
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",

    # Third party
    "rest_framework",
    "rest_framework_simplejwt",
    "rest_framework_simplejwt.token_blacklist",
    "django_extensions",
    "corsheaders",
    "djoser",
    "django_filters",

    # Local apps
    "accounts",
    "manage_personnel",
    "dashboard",
    "activities",
    "bank_accounts",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "core.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "core.wsgi.application"

# Database
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.getenv("DB_NAME", "bota"),
        "USER": os.getenv("DB_USER", "postgres"),
        "PASSWORD": os.getenv("DB_PASSWORD", ""),
        "HOST": os.getenv("DB_HOST", "localhost"),
        "PORT": os.getenv("DB_PORT", "5432"),
        "OPTIONS": {"options": "-c client_encoding=UTF8"},
        "CONN_MAX_AGE": int(os.getenv("DB_CONN_MAX_AGE", 0)),
    }
}

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

# Internationalization
LANGUAGE_CODE = "en-us"
TIME_ZONE = os.getenv("TIME_ZONE", "UTC")
USE_I18N = True
USE_TZ = True

# Static / media
STATIC_URL = "/static/"
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Custom user model
AUTH_USER_MODEL = os.getenv("AUTH_USER_MODEL", "manage_personnel.User")

# REST Framework + Simple JWT configuration
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.LimitOffsetPagination",
    "PAGE_SIZE": 25,
    "DEFAULT_FILTER_BACKENDS": (
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.SearchFilter",
        "rest_framework.filters.OrderingFilter",
    ),
    "DEFAULT_RENDERER_CLASSES": [
        "rest_framework.renderers.JSONRenderer",
    ],
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=int(os.getenv("JWT_ACCESS_MINUTES", 15))),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=int(os.getenv("JWT_REFRESH_DAYS", 7))),
    "ROTATE_REFRESH_TOKENS": os.getenv("JWT_ROTATE_REFRESH_TOKENS", "True").lower() in ("1", "true", "yes"),
    "BLACKLIST_AFTER_ROTATION": os.getenv("JWT_BLACKLIST_AFTER_ROTATION", "True").lower() in ("1", "true", "yes"),
    "AUTH_HEADER_TYPES": tuple(os.getenv("JWT_AUTH_HEADER_TYPES", "Bearer").split(",")),
}

# CORS (development)
CORS_ALLOW_ALL_ORIGINS = os.getenv("CORS_ALLOW_ALL_ORIGINS", "True").lower() in ("1", "true", "yes")

# Cookies / security defaults (override in production via env)
SESSION_COOKIE_SECURE = os.getenv("SESSION_COOKIE_SECURE", "False").lower() in ("1", "true", "yes")
CSRF_COOKIE_SECURE = os.getenv("CSRF_COOKIE_SECURE", "False").lower() in ("1", "true", "yes")
SESSION_COOKIE_SAMESITE = os.getenv("SESSION_COOKIE_SAMESITE", "Lax")

# Authentication backends
AUTHENTICATION_BACKENDS = ["django.contrib.auth.backends.ModelBackend"]

# Email defaults for development
EMAIL_BACKEND = os.getenv("EMAIL_BACKEND", "django.core.mail.backends.console.EmailBackend")
DEFAULT_FROM_EMAIL = os.getenv("DEFAULT_FROM_EMAIL", "webmaster@localhost")

# FERNET KEYS configuration
# Expect FERNET_KEYS as either a JSON list string or a single base64 key string in the environment.
# In production DO NOT fallback to empty values; in DEBUG you may supply FERNET_DEV_KEY for convenience.
FERNET_KEYS = None
_raw = os.environ.get("FERNET_KEYS") or os.getenv("FERNET_KEYS")
if _raw:
    try:
        FERNET_KEYS = json.loads(_raw) if isinstance(_raw, str) and _raw.strip().startswith("[") else [_raw]
    except Exception:
        FERNET_KEYS = [_raw]

if not FERNET_KEYS:
    if DEBUG:
        _dev = os.environ.get("FERNET_DEV_KEY")
        if _dev:
            FERNET_KEYS = [_dev]
        else:
            FERNET_KEYS = None
    else:
        FERNET_KEYS = None

# Helpful debug / dev flags
# Set to True only in development when you understand consequences
SHOW_SQL = os.getenv("SHOW_SQL", "False").lower() in ("1", "true", "yes")
if SHOW_SQL:
    LOGGING = {
        "version": 1,
        "disable_existing_loggers": False,
        "filters": {"require_debug_true": {"()": "django.utils.log.RequireDebugTrue"}},
        "handlers": {
            "console": {
                "level": "DEBUG",
                "class": "logging.StreamHandler",
            }
        },
        "loggers": {
            "django.db.backends": {
                "level": "DEBUG",
                "handlers": ["console"],
                "propagate": False,
            }
        },
    }

# Additional sensible defaults
# Limit upload size in bytes if needed (example: 10MB)
DATA_UPLOAD_MAX_MEMORY_SIZE = int(os.getenv("DATA_UPLOAD_MAX_MEMORY_SIZE", 10485760))

# End of settings