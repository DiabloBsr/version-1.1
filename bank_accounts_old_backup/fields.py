# bank_accounts/fields.py
import json
import os
from typing import Optional, List
from django.conf import settings
from django.db import models
from cryptography.fernet import Fernet, InvalidToken

# cache for Fernet instances
_FERNET_CACHE: List[Fernet] = []
_PRIMARY_FERNET: Optional[Fernet] = None


def _load_keys_from_settings_or_env() -> List[bytes]:
    raw = getattr(settings, "FERNET_KEYS", None)
    if raw is None:
        raw = os.environ.get("FERNET_KEYS")
    if raw is None:
        return []
    if isinstance(raw, (list, tuple)):
        keys = raw
    else:
        try:
            keys = json.loads(raw)
        except Exception:
            # treat as single raw key string
            keys = [raw]
    # normalize to bytes
    normalized = []
    for k in keys:
        if k is None:
            continue
        if isinstance(k, str):
            normalized.append(k.encode("utf-8"))
        elif isinstance(k, bytes):
            normalized.append(k)
        else:
            # fallback: convert to str then bytes
            normalized.append(str(k).encode("utf-8"))
    return normalized


def _ensure_fernets_loaded():
    global _FERNET_CACHE, _PRIMARY_FERNET
    if _FERNET_CACHE:
        return
    keys = _load_keys_from_settings_or_env()
    if not keys:
        raise RuntimeError(
            "FERNET_KEYS is not configured. Set settings.FERNET_KEYS or the environment variable FERNET_KEYS."
        )
    for k in keys:
        # ensure the key is valid base64 length expected by Fernet
        try:
            _FERNET_CACHE.append(Fernet(k))
        except Exception as exc:
            raise RuntimeError(f"Invalid Fernet key provided: {exc}") from exc
    _PRIMARY_FERNET = _FERNET_CACHE[0]


def _get_primary_fernet() -> Fernet:
    _ensure_fernets_loaded()
    return _PRIMARY_FERNET  # type: ignore


def _get_all_fernets() -> List[Fernet]:
    _ensure_fernets_loaded()
    return list(_FERNET_CACHE)


class EncryptedTextField(models.TextField):
    description = "Text field encrypted with Fernet"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def deconstruct(self):
        name, path, args, kwargs = super().deconstruct()
        # no special args to preserve, but include for future-proofing
        return name, path, args, kwargs

    def get_prep_value(self, value):
        if value is None:
            return None
        if value == "":
            return ""
        f = _get_primary_fernet()
        if isinstance(value, str):
            value_bytes = value.encode("utf-8")
        else:
            value_bytes = str(value).encode("utf-8")
        token = f.encrypt(value_bytes)
        return token.decode("utf-8")

    def from_db_value(self, value, expression, connection):
        if value is None:
            return None
        if value == "":
            return ""
        # try all keys for decryption (rotation support)
        for f in _get_all_fernets():
            try:
                return f.decrypt(value.encode("utf-8")).decode("utf-8")
            except InvalidToken:
                continue
        # if none worked, return raw token to surface issue
        return value

    def to_python(self, value):
        # called on assignment and deserialization
        if value is None:
            return None
        if isinstance(value, str):
            if value == "":
                return ""
            # try to decrypt; if fails, assume plaintext
            for f in _get_all_fernets():
                try:
                    return f.decrypt(value.encode("utf-8")).decode("utf-8")
                except InvalidToken:
                    continue
            return value
        return value