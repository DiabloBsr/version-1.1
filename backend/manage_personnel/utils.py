# manage_personnel/utils.py
import base64
import io
import qrcode
import pyotp
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
    except InvalidToken as e:
        raise

# TOTP helpers
def generate_totp_secret() -> str:
    return pyotp.random_base32()

def get_provisioning_uri(secret: str, user_email: str, issuer_name: str = "ManagePersonnel") -> str:
    totp = pyotp.TOTP(secret)
    return totp.provisioning_uri(name=user_email, issuer_name=issuer_name)

def generate_qr_base64_from_uri(uri: str) -> str:
    qr = qrcode.QRCode(box_size=4, border=2)
    qr.add_data(uri)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buffered = io.BytesIO()
    img.save(buffered, format="PNG")
    return base64.b64encode(buffered.getvalue()).decode()

def verify_totp(secret: str, otp: str) -> bool:
    totp = pyotp.TOTP(secret)
    return totp.verify(otp, valid_window=1)