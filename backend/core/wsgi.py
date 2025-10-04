"""
WSGI config for core project.

It exposes the WSGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/5.2/howto/deployment/wsgi/
"""

import os

from django.core.wsgi import get_wsgi_application
from django.conf import settings
print("SERVER DB:", settings.DATABASES)
print("SERVER FERNET_KEYS:", getattr(settings, "FERNET_KEYS", None))

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'core.settings')

application = get_wsgi_application()
