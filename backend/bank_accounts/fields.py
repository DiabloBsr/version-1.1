# bank_accounts/fields.py
import base64
import os
from typing import Optional
from django.conf import settings
from django.db import models
from cryptography.fernet import Fernet, InvalidToken

# Attendre une variable d'environnement FERNET_KEYS contenant JSON list ou une string clé
# Ex: FERNET_KEYS='["<base64_key>"]'
def _get_primary_fernet() -> Fernet:
    keys = getattr(settings, "FERNET_KEYS", None)
    if not keys:
        # try environment fallback
        raw = os.environ.get("FERNET_KEYS")
        if not raw:
            raise RuntimeError("FERNET_KEYS not set in settings or environment")
        import json
        keys = json.loads(raw)
    if isinstance(keys, str):
        import json
        keys = json.loads(keys)
    if not keys:
        raise RuntimeError("FERNET_KEYS is empty")
    # first key is primary for encryption
    primary = keys[0]
    if isinstance(primary, str):
        primary = primary.encode()
    return Fernet(primary)

def _get_all_fernets():
    keys = getattr(settings, "FERNET_KEYS", None)
    if not keys:
        import os, json
        keys = json.loads(os.environ.get("FERNET_KEYS") or "[]")
    if isinstance(keys, str):
        import json
        keys = json.loads(keys)
    fernets = []
    for k in keys:
        kk = k.encode() if isinstance(k, str) else k
        fernets.append(Fernet(kk))
    return fernets

class EncryptedTextField(models.TextField):
    description = "Text field encrypted with Fernet"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def get_prep_value(self, value):
        if value is None:
            return None
        if value == "":
            return ""
        f = _get_primary_fernet()
        token = f.encrypt(value.encode("utf-8"))
        return token.decode("utf-8")

    def from_db_value(self, value, expression, connection):
        if value is None:
            return None
        if value == "":
            return ""
        # try all keys for decryption (rotate support)
        for f in _get_all_fernets():
            try:
                return f.decrypt(value.encode("utf-8")).decode("utf-8")
            except InvalidToken:
                continue
        # if none worked, return raw value to avoid crash (but surface for investigation)
        return value

    def to_python(self, value):
        # called on assignment and deserialization
        if value is None:
            return None
        if isinstance(value, str):
            # If looks like an encrypted token (b64 with two dots), try to decrypt
            try:
                # attempt decrypt with all keys
                for f in _get_all_fernets():
                    try:
                        return f.decrypt(value.encode("utf-8")).decode("utf-8")
                    except InvalidToken:
                        continue
            except Exception:
                pass
            # fallback: return as-is (plain text)
            return value
        return value