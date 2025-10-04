# bank_accounts/fields.py
"""
EncryptedTextField backed by cryptography.fernet Fernet keys.
- Expects settings.FERNET_KEYS to be a list of base64 keys or an environment variable FERNET_KEYS
  containing a JSON list or a plain string key.
- The first key is used for encryption; all keys are tried for decryption (rotation support).
- Raises a clear RuntimeError when no usable keys are configured (fail fast in prod).
- Implements deconstruct() to be migration-friendly.
"""
import json
import os
from typing import List, Optional
from django.conf import settings
from django.db import models
from cryptography.fernet import Fernet, InvalidToken

# internal caches to avoid recreating Fernet objects on each call
_FERNET_CACHE: List[Fernet] = []
_PRIMARY_FERNET: Optional[Fernet] = None


def _load_raw_keys() -> List[str]:
    """
    Load raw keys from settings.FERNET_KEYS or the environment variable FERNET_KEYS.
    Acceptable formats:
      - settings.FERNET_KEYS = ["<base64>", "<base64>"]
      - environment FERNET_KEYS = '["<base64>", "<base64>"]'
      - environment FERNET_KEYS = '<base64>'
    Returns a list of raw strings (not bytes). Empty list if none found.
    """
    raw = getattr(settings, "FERNET_KEYS", None)
    if raw is None:
        raw = os.environ.get("FERNET_KEYS")
    if raw is None:
        return []
    if isinstance(raw, (list, tuple)):
        return [str(x) for x in raw if x]
    if isinstance(raw, str):
        s = raw.strip()
        if s.startswith("["):
            try:
                parsed = json.loads(s)
                if isinstance(parsed, (list, tuple)):
                    return [str(x) for x in parsed if x]
            except Exception:
                # fallthrough to treat raw as single key
                pass
        return [s]
    # fallback: stringify any other type
    return [str(raw)]


def _ensure_fernets_loaded():
    """
    Populate _FERNET_CACHE and _PRIMARY_FERNET from raw keys.
    Raises RuntimeError if no keys found or if keys are invalid.
    """
    global _FERNET_CACHE, _PRIMARY_FERNET
    if _FERNET_CACHE:
        return
    raw_keys = _load_raw_keys()
    if not raw_keys:
        raise RuntimeError(
            "FERNET_KEYS is not configured. Set settings.FERNET_KEYS or the environment variable FERNET_KEYS."
        )
    for k in raw_keys:
        # ensure key is bytes for Fernet
        kb = k.encode("utf-8") if isinstance(k, str) else k
        try:
            _FERNET_CACHE.append(Fernet(kb))
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

    def deconstruct(self):
        name, path, args, kwargs = super().deconstruct()
        return name, path, args, kwargs

    def get_prep_value(self, value):
        """
        Called by Django before writing to the DB.
        Returns None or empty string as-is; encrypts non-empty strings.
        """
        if value is None:
            return None
        if value == "":
            return ""
        f = _get_primary_fernet()
        if not isinstance(value, (str, bytes)):
            value = str(value)
        value_bytes = value.encode("utf-8") if isinstance(value, str) else value
        token = f.encrypt(value_bytes)
        return token.decode("utf-8")

    def from_db_value(self, value, expression, connection):
        """
        Called when loading from DB.
        Tries all configured Fernets for decryption. If none succeed, returns raw value.
        """
        if value is None:
            return None
        if value == "":
            return ""
        # Try decrypt with all keys (rotation support)
        for f in _get_all_fernets():
            try:
                return f.decrypt(value.encode("utf-8")).decode("utf-8")
            except (InvalidToken, Exception):
                continue
        # Return raw stored value to surface problem without crashing
        return value

    def to_python(self, value):
        """
        Called during deserialization and assignment.
        If value looks encrypted, attempt to decrypt; otherwise return as-is.
        """
        if value is None:
            return None
        if isinstance(value, str):
            if value == "":
                return ""
            # Try decrypt with all keys; if fails, return plaintext
            for f in _get_all_fernets():
                try:
                    return f.decrypt(value.encode("utf-8")).decode("utf-8")
                except (InvalidToken, Exception):
                    continue
            return value
        return value