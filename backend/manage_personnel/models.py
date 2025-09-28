import uuid
from datetime import date
from django.db import models
from django.conf import settings
from django.utils.translation import gettext_lazy as _
from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(_("email address"), unique=True)
    phone_number = models.CharField(max_length=25, blank=True, null=True, unique=True)

    # Champs MFA
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

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="profile",
    )
    nom = models.CharField(max_length=100)
    prenom = models.CharField(max_length=100)
    sexe = models.CharField(max_length=1, choices=SEX_CHOICES)
    date_naissance = models.DateField()
    lieu_naissance = models.CharField(max_length=100)
    cin_numero = models.CharField(max_length=20, unique=True)
    cin_date_delivrance = models.DateField()
    situation_matrimoniale = models.CharField(max_length=20, choices=MARITAL_CHOICES)
    nombre_enfants = models.IntegerField(default=0)
    telephone = models.CharField(max_length=20, blank=True)
    email = models.EmailField(blank=True)
    adresse = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    @property
    def age(self):
        today = date.today()
        return today.year - self.date_naissance.year - (
            (today.month, today.day) < (self.date_naissance.month, self.date_naissance.day)
        )

    def anniversaire_est_proche(self, jours=7):
        today = date.today()
        anniversaire = self.date_naissance.replace(year=today.year)
        delta = (anniversaire - today).days
        return 0 <= delta <= jours

    def __str__(self):
        return f"{self.nom} {self.prenom} ({self.user.email if self.user else 'no-user'})"

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


class BankAccount(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    profile = models.ForeignKey(Profile, on_delete=models.CASCADE, related_name="bank_accounts")
    bank_name = models.CharField(max_length=100, default="BFV")
    bank_code = models.CharField(max_length=20)
    organisme_code = models.CharField(max_length=20, blank=True)
    agency = models.CharField(max_length=100, blank=True)
    account_number = models.CharField(max_length=50)
    rib_key = models.CharField(max_length=10, blank=True)
    bk_code = models.CharField(max_length=10, blank=True)
    is_primary = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = (("profile", "account_number"),)
        ordering = ("-created_at",)

    def __str__(self):
        return f"{self.bank_name} - {self.account_number}"