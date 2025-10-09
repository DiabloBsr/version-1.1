import uuid
from datetime import date
from django.db import models
from django.conf import settings
from django.utils.translation import gettext_lazy as _
from django.contrib.auth.models import AbstractUser
from django.core.validators import FileExtensionValidator

class User(AbstractUser):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(_("email address"), unique=True)
    phone_number = models.CharField(max_length=25, blank=True, null=True, unique=True)

    is_mfa_enabled = models.BooleanField(default=False)
    totp_secret = models.CharField(max_length=64, null=True, blank=True)
    is_mfa_verified = models.BooleanField(default=False)
    preferred_2fa = models.CharField(
        max_length=20,
        choices=(("totp", "TOTP"), ("sms", "SMS")),
        default="totp",
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["username"]

    def __str__(self):
        return self.email

    @property
    def full_name(self):
        if hasattr(self, "profile") and self.profile is not None:
            nom = (self.profile.nom or "").strip()
            prenom = (self.profile.prenom or "").strip()
            full = f"{nom} {prenom}".strip()
            return full if full else self.username
        return self.username

    def enable_mfa(self, method="totp"):
        self.is_mfa_enabled = True
        self.preferred_2fa = method
        self.save(update_fields=["is_mfa_enabled", "preferred_2fa"])

    def disable_mfa(self):
        self.is_mfa_enabled = False
        self.totp_secret = None
        self.is_mfa_verified = False
        self.save(update_fields=["is_mfa_enabled", "totp_secret", "is_mfa_verified"])

    class Meta:
        ordering = ("-created_at",)
        verbose_name = _("user")
        verbose_name_plural = _("users")


class Profile(models.Model):
    SEX_CHOICES = (("M", "Masculin"), ("F", "Féminin"))
    MARITAL_CHOICES = (
        ("celibataire", "Célibataire"),
        ("marie", "Marié(e)"),
        ("veuf", "Veuf(ve)"),
        ("divorce", "Divorcé(e)"),
    )
    prefs = models.JSONField(default=dict)
    ROLE_CHOICES = (
        ("admin", "Administrateur"),
        ("user", "Utilisateur"),
        ("manager", "Gestionnaire"),
    )

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="profile",
    )
    nom = models.CharField(max_length=100, blank=True)
    prenom = models.CharField(max_length=100, blank=True)
    sexe = models.CharField(max_length=1, choices=SEX_CHOICES, blank=True)
    date_naissance = models.DateField(null=True, blank=True)
    lieu_naissance = models.CharField(max_length=100, blank=True)
    cin_numero = models.CharField(max_length=50, unique=True, null=True, blank=True)
    cin_date_delivrance = models.CharField(max_length=100, blank=True)
    situation_matrimoniale = models.CharField(
        max_length=20, choices=MARITAL_CHOICES, blank=True
    )
    nombre_enfants = models.IntegerField(default=0)
    telephone = models.CharField(max_length=20, blank=True)
    email = models.EmailField(blank=True)
    adresse = models.TextField(blank=True)

    role = models.CharField(
        max_length=20,
        choices=ROLE_CHOICES,
        default="user",
        help_text="Rôle de l'utilisateur pour la navigation et les permissions",
    )

    photo = models.ImageField(
        upload_to="profiles/",
        null=True,
        blank=True,
        validators=[FileExtensionValidator(allowed_extensions=["jpg", "jpeg", "png"])],
    )

    created_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True, help_text="Actif pour le service (auto/dé)activation")
    last_active_at = models.DateTimeField(null=True, blank=True, help_text="Dernier accès connu")


    @property
    def age(self):
        if not self.date_naissance:
            return None
        today = date.today()
        return (
            today.year
            - self.date_naissance.year
            - (
                (today.month, today.day)
                < (self.date_naissance.month, self.date_naissance.day)
            )
        )

    def anniversaire_est_proche(self, jours=7):
        if not self.date_naissance:
            return False
        today = date.today()
        anniversaire = self.date_naissance.replace(year=today.year)
        delta = (anniversaire - today).days
        return 0 <= delta <= jours

    def __str__(self):
        user_email = self.user.email if self.user else "no-user"
        return f"{self.nom or ''} {self.prenom or ''} ({user_email})".strip()

    class Meta:
        ordering = ("-created_at",)
        verbose_name = _("profile")
        verbose_name_plural = _("profiles")


class Personnel(models.Model):
    BUDGET_CHOICES = (
        ("general", "Budget Général"),
        ("cfu", "CFU"),
        ("etrangere", "Etrangère"),
    )

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    profile = models.OneToOneField(Profile, on_delete=models.CASCADE, related_name="personnel")
    budget_type = models.CharField(max_length=20, choices=BUDGET_CHOICES)
    groupe_sanguin = models.CharField(max_length=5, blank=True)
    poste_precedent = models.CharField(max_length=100, blank=True)
    specialite = models.CharField(max_length=100, blank=True)
    autres_diplomes = models.TextField(blank=True)
    observation = models.TextField(blank=True)
    ref_affectation = models.CharField(max_length=100, blank=True)
    date_affectation = models.DateField(null=True, blank=True)
    date_entree_admin = models.DateField(null=True, blank=True)
    date_entree_hjra = models.DateField(null=True, blank=True)
    lieu_affectation = models.CharField(max_length=100, blank=True)
    conjoint_nom = models.CharField(max_length=100, blank=True)
    conjoint_date_naiss = models.DateField(null=True, blank=True)

    def __str__(self):
        return f"Personnel: {self.profile}"

    class Meta:
        ordering = ("-id",)