import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE','core.settings')
import django
django.setup()

from django.contrib.auth import get_user_model
User = get_user_model()
u = User.objects.filter(username__iexact='olivio').first()
if not u:
    User.objects.create_superuser(username='olivio', email='oliviofanomezantsoa@gmail.com', password='Tojonirina@2506')
else:
    u.is_active = True
    u.is_staff = True
    u.is_superuser = True
    u.set_password('Tojonirina@2506')
    u.save()
    print('updated', u)