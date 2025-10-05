# bank_accounts/signals.py
from django.db.models.signals import pre_save, post_save, post_delete
from django.dispatch import receiver
from django.utils import timezone
from django.apps import apps
import logging

from .models import BankAccount

logger = logging.getLogger(__name__)
Activity = apps.get_model("activities", "Activity")


def _fields_of_interest():
    # champs à surveiller pour produire un diff utile
    return [
        "bank_name",
        "bank_code",
        "agency",
        "currency",
        "iban_encrypted",
        "account_number_encrypted",
        "masked_account",
        "is_primary",
        "status",
    ]


def _serialize_diff(old, new):
    diff = {}
    for f in _fields_of_interest():
        old_v = getattr(old, f, None) if old is not None else None
        new_v = getattr(new, f, None)
        if old_v != new_v:
            diff[f] = {"old": old_v, "new": new_v}
    return diff


def _safe_text(action, instance, diff):
    # texte lisible minimal pour l'activité (utile en admin / debug)
    profile_id = getattr(instance.profile, "id", getattr(instance.profile, "pk", None))
    if diff:
        changed = ", ".join(diff.keys())
        return f"Compte bancaire {action} — {changed}"
    return f"Compte bancaire {action}"


def _activity_create(**kwargs):
    """
    Create Activity in a best-effort, non-raising way from signals.
    Attach user if provided, otherwise create without user if the field allows null.
    """
    try:
        Activity.objects.create(**kwargs)
    except Exception as exc:
        # try without user if user caused integrity error and field allows null
        try:
            if "user" in kwargs:
                del kwargs["user"]
                field_user = Activity._meta.get_field("user")
                if field_user.null or getattr(field_user, "blank", False):
                    Activity.objects.create(**kwargs)
                else:
                    logger.debug("Activity.user required but not available; skipping creation")
        except Exception:
            logger.exception("Failed to create Activity in signal: %s", exc)


@receiver(pre_save, sender=BankAccount)
def _bankaccount_pre_save(sender, instance, **kwargs):
    """
    Snapshot previous state for later comparison in post_save.
    """
    if instance.pk:
        try:
            instance._pre_save_obj = BankAccount.objects.filter(pk=instance.pk).first()
        except Exception as e:
            logger.exception("pre_save snapshot failed: %s", e)
            instance._pre_save_obj = None
    else:
        instance._pre_save_obj = None


@receiver(post_save, sender=BankAccount)
def bankaccount_post_save(sender, instance, created, **kwargs):
    """
    On create or update, compute diff and ALWAYS create a new Activity entry.
    Do not overwrite existing Activity rows for the same bank account.
    """
    try:
        old = getattr(instance, "_pre_save_obj", None)
        action = "ajouté" if created else "modifié"
        diff = _serialize_diff(old, instance)

        # skip if update but no meaningful change
        if not created and not diff:
            return

        timestamp = timezone.now()
        external_id = f"bank_account:{instance.id}"

        meta = {
            "account_id": str(instance.id),
            "profile_id": str(getattr(instance.profile, "id", getattr(instance.profile, "pk", None))) if getattr(instance, "profile", None) is not None else None,
            "action": "create" if created else "update",
            "diff": diff,
        }

        text = _safe_text(action, instance, diff)

        # try to determine user from profile
        user = None
        if getattr(instance, "profile", None) is not None:
            user = getattr(instance.profile, "user", None)

        create_kwargs = {
            "text": text,
            "type": "bank_account_change",
            "meta": meta,
            "timestamp": timestamp,
            "external_id": external_id,
            "visible": True,
        }

        if user is not None:
            create_kwargs["user"] = user

        _activity_create(**create_kwargs)

    except Exception as exc:
        logger.exception("Failed to create Activity for BankAccount post_save: %s", exc)


@receiver(post_delete, sender=BankAccount)
def bankaccount_post_delete(sender, instance, **kwargs):
    """
    Record deletion as a new Activity (do not update/overwrite prior activities).
    """
    try:
        action = "supprimé"
        diff = {"status": {"old": getattr(instance, "status", None), "new": "deleted"}}
        timestamp = timezone.now()
        external_id = f"bank_account:{instance.id}"
        meta = {
            "account_id": str(instance.id),
            "profile_id": str(getattr(instance.profile, "id", getattr(instance.profile, "pk", None))) if getattr(instance, "profile", None) is not None else None,
            "action": "delete",
            "diff": diff,
        }
        text = _safe_text(action, instance, diff)

        user = None
        if getattr(instance, "profile", None) is not None:
            user = getattr(instance.profile, "user", None)

        create_kwargs = {
            "text": text,
            "type": "bank_account_change",
            "meta": meta,
            "timestamp": timestamp,
            "external_id": external_id,
            "visible": False,
        }

        if user is not None:
            create_kwargs["user"] = user

        _activity_create(**create_kwargs)

    except Exception as exc:
        logger.exception("Failed to create Activity for BankAccount post_delete: %s", exc)