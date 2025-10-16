# manage_personnel/utils.py
import base64
import io
from django.conf import settings
from cryptography.fernet import Fernet, InvalidToken

# Fernet helper (MVP: uses env FERNET_KEY; in prod use KMS)
def _get_fernet():
    key = getattr(settings, "FERNET_KEY", None)
    if not key:
        raise RuntimeError("FERNET_KEY not configured in settings or env")
    return Fernet(key)

def encrypt_bytes(data: bytes) -> bytes:
    f = _get_fernet()
    return f.encrypt(data)

def decrypt_bytes(token: bytes) -> bytes:
    f = _get_fernet()
    try:
        return f.decrypt(token)
    except InvalidToken:
        raise