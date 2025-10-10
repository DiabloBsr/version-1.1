import pytest
from django.db import models, connection
from cryptography.fernet import Fernet
from bank_accounts import fields


def make_key():
    return Fernet.generate_key().decode("utf-8")


def create_temp_model(name="Dummy", field=None):
    """
    Crée un modèle temporaire avec un EncryptedTextField
    et crée la table en base via schema_editor.
    """
    attrs = {
        "__module__": __name__,
        "secret": field or fields.EncryptedTextField(),
        "Meta": type("Meta", (), {"app_label": "bank_accounts", "managed": True}),
    }
    model = type(name, (models.Model,), attrs)

    # Créer la table
    with connection.schema_editor() as schema_editor:
        schema_editor.create_model(model)

    return model


def drop_temp_model(model):
    """Supprime la table du modèle temporaire."""
    with connection.schema_editor() as schema_editor:
        schema_editor.delete_model(model)


@pytest.fixture(autouse=True)
def reset_fernet_cache():
    # Nettoyer le cache avant chaque test
    fields._FERNET_CACHE.clear()
    fields._PRIMARY_FERNET = None
    yield
    fields._FERNET_CACHE.clear()
    fields._PRIMARY_FERNET = None


@pytest.mark.django_db
def test_runtime_error_if_no_keys(settings):
    fields._FERNET_CACHE.clear()
    fields._PRIMARY_FERNET = None
    settings.FERNET_KEYS = None

    f = fields.EncryptedTextField()
    with pytest.raises(RuntimeError):
        f.get_prep_value("secret")


@pytest.mark.django_db
def test_encrypt_and_decrypt_roundtrip(settings):
    settings.FERNET_KEYS = [make_key()]
    Dummy = create_temp_model("Dummy1")

    obj = Dummy.objects.create(secret="hello world")
    obj.refresh_from_db()
    assert obj.secret == "hello world"

    drop_temp_model(Dummy)


@pytest.mark.django_db
def test_none_and_empty_are_preserved(settings):
    settings.FERNET_KEYS = [make_key()]
    Dummy = create_temp_model(
        "Dummy2",
        field=fields.EncryptedTextField(null=True, blank=True)  # ✅ autoriser NULL
    )

    obj1 = Dummy.objects.create(secret=None)
    obj2 = Dummy.objects.create(secret="")
    obj1.refresh_from_db()
    obj2.refresh_from_db()
    assert obj1.secret is None
    assert obj2.secret == ""

    drop_temp_model(Dummy)


@pytest.mark.django_db
def test_key_rotation(settings):
    k1 = make_key()
    k2 = make_key()
    settings.FERNET_KEYS = [k1, k2]
    Dummy = create_temp_model("Dummy3")

    obj = Dummy.objects.create(secret="rotated")
    obj.refresh_from_db()
    assert obj.secret == "rotated"

    drop_temp_model(Dummy)


@pytest.mark.django_db
def test_runtime_error_if_no_keys(settings, monkeypatch):
    # Forcer un reset complet
    fields._FERNET_CACHE.clear()
    fields._PRIMARY_FERNET = None

    # Supprimer toute config de clés
    settings.FERNET_KEYS = None
    monkeypatch.delenv("FERNET_KEYS", raising=False)

    f = fields.EncryptedTextField()
    with pytest.raises(RuntimeError):
        f.get_prep_value("secret")
