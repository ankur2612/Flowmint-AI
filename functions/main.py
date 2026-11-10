"""FLOWMINT AI trusted backend (Firebase Cloud Functions, Python).

All PayPal operations run here. The client never sends prices: shopping
orders are priced from `catalog_products` and donations are validated
against `campaigns`. Payment records under users/{uid}/orders|donations are
written only by these functions (enforced by Firestore rules), and a payment
is marked COMPLETED only after PayPal reports a completed capture, either in
the capture response or through a verified webhook.
"""

from __future__ import annotations

import calendar
import hashlib
import json
import os
import re
from datetime import datetime, timedelta, timezone
from typing import Any

from firebase_admin import firestore, initialize_app, messaging
from firebase_functions import https_fn, logger, options, params, scheduler_fn
from google.cloud.firestore_v1.base_query import FieldFilter

import requests

from paypal_client import PayPalClient, PayPalError, approve_link, first_capture

initialize_app()
options.set_global_options(region="asia-south1", max_instances=10)

PAYPAL_CLIENT_ID = params.SecretParam("PAYPAL_CLIENT_ID")
PAYPAL_CLIENT_SECRET = params.SecretParam("PAYPAL_CLIENT_SECRET")
PAYPAL_ENV = params.StringParam("PAYPAL_ENV", default="sandbox")
PAYPAL_WEBHOOK_ID = params.StringParam("PAYPAL_WEBHOOK_ID", default="")
PAYPAL_RETURN_BASE_URL = params.StringParam("PAYPAL_RETURN_BASE_URL", default="")
MERCHANT_NAME = params.StringParam("MERCHANT_NAME", default="FLOWMINT Store")
REFUND_WINDOW_DAYS = params.IntParam("REFUND_WINDOW_DAYS", default=30)

_SECRETS = [PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET]
_KEY_PATTERN = re.compile(r"^[A-Za-z0-9-]{8,64}$")
_COLLECTIONS = {"shopping": "orders", "donation": "donations"}
_FINAL = {"COMPLETED", "FAILED", "CANCELLED", "REFUNDED", "PARTIALLY_REFUNDED"}
# Currencies PayPal expresses without decimals; minor units here assume two.
_UNSUPPORTED_CURRENCIES = {"JPY", "HUF", "TWD"}
_MAX_DONATION_MINOR = 100_000_000

Code = https_fn.FunctionsErrorCode

# Per-user limits for payment endpoints, enforced with Firestore transactions
# so concurrent requests cannot exceed them (calls per minute).
RATE_LIMITS = {"create": 5, "capture": 5, "refund": 3, "cancel": 10}
# A capture "in progress" longer than this is treated as abandoned (for
# example the instance died) and may be retried; the retry reconciles with
# PayPal through the same PayPal-Request-Id.
_CAPTURE_LOCK_SECONDS = 120


def _rate_limit(uid: str, operation: str, now: datetime | None = None) -> None:
    limit = RATE_LIMITS[operation]
    now = now or datetime.now(timezone.utc)
    window = now.strftime("%Y%m%d%H%M")
    ref = _db().collection("rate_limits").document(f"{uid}_{operation}")

    @firestore.transactional
    def consume(tx) -> bool:
        snap = ref.get(transaction=tx)
        data = snap.to_dict() if snap.exists else {}
        count = data.get("count", 0) if data.get("window") == window else 0
        if count >= limit:
            return False
        tx.set(ref, {"window": window, "count": count + 1})
        return True

    if not consume(_db().transaction()):
        raise https_fn.HttpsError(
            Code.RESOURCE_EXHAUSTED,
            f"Too many requests. Please wait {60 - now.second} seconds and try again.")


def _request_fingerprint(kind: str, data: dict[str, Any]) -> str:
    """Hash of the payable content, so an idempotency key cannot be reused
    for a different cart or donation."""
    if kind == "shopping":
        items = sorted((str(i.get("productId")), i.get("quantity"))
                       for i in data.get("items") or [] if isinstance(i, dict))
        payload: Any = {"items": items}
    else:
        payload = {"campaignId": data.get("campaignId"), "amountMinor": data.get("amountMinor")}
    return hashlib.sha256(json.dumps([kind, payload], sort_keys=True, default=str).encode()).hexdigest()


def _db():
    return firestore.client()


def _paypal() -> PayPalClient:
    try:
        return PayPalClient(PAYPAL_CLIENT_ID.value, PAYPAL_CLIENT_SECRET.value, PAYPAL_ENV.value)
    except ValueError as e:
        raise https_fn.HttpsError(Code.FAILED_PRECONDITION,
                                  "PayPal is not configured for this project.") from e


def _uid(req: https_fn.CallableRequest) -> str:
    if req.auth is None:
        raise https_fn.HttpsError(Code.UNAUTHENTICATED, "Sign in to continue.")
    return req.auth.uid


def _invalid(message: str) -> https_fn.HttpsError:
    return https_fn.HttpsError(Code.INVALID_ARGUMENT, message)


def _value(minor: int) -> str:
    return f"{minor // 100}.{minor % 100:02d}"


def _return_urls() -> tuple[str, str]:
    base = PAYPAL_RETURN_BASE_URL.value.rstrip("/")
    if not base:
        project = os.environ.get("GCLOUD_PROJECT", "flowmint")
        base = f"https://{project}.web.app/paypal"
    return f"{base}/return", f"{base}/cancel"


def _record_ref(uid: str, kind: str, record_id: str):
    collection = _COLLECTIONS.get(kind)
    if collection is None or not _KEY_PATTERN.match(record_id or ""):
        raise _invalid("Unknown payment record.")
    return _db().collection("users").document(uid).collection(collection).document(record_id)


def _session(record_id: str, kind: str, data: dict[str, Any]) -> dict[str, Any]:
    return_url, cancel_url = _return_urls()
    return {
        "recordId": record_id,
        "kind": kind,
        "paypalOrderId": data.get("paypalOrderId"),
        "approveUrl": data.get("approveUrl") or "",
        "returnUrl": return_url,
        "cancelUrl": cancel_url,
        "amountMinor": data.get("amountMinor"),
        "currency": data.get("currency"),
        "status": data.get("status"),
    }


def _paypal_failure(e: PayPalError, action: str) -> https_fn.HttpsError:
    # debug_id lets PayPal support trace the call; it contains no secrets.
    logger.warn(f"PayPal {action} failed", status=e.status, issue=e.name, debug_id=e.debug_id)
    return https_fn.HttpsError(Code.UNAVAILABLE if e.status >= 500 else Code.FAILED_PRECONDITION,
                               f"PayPal could not {action}. Please try again.")


# Payable amounts are computed here from trusted records, never from the client.

def _prepare_shopping(data: dict[str, Any]) -> dict[str, Any]:
    raw_items = data.get("items")
    if not isinstance(raw_items, list) or not 1 <= len(raw_items) <= 20:
        raise _invalid("Your cart is empty or too large.")
    quantities: dict[str, int] = {}
    for item in raw_items:
        pid = item.get("productId") if isinstance(item, dict) else None
        qty = item.get("quantity") if isinstance(item, dict) else None
        if not isinstance(pid, str) or not isinstance(qty, int) or not 1 <= qty <= 10:
            raise _invalid("Invalid cart item.")
        quantities[pid] = quantities.get(pid, 0) + qty

    refs = [_db().collection("catalog_products").document(pid) for pid in quantities]
    lines, currency, total = [], None, 0
    for snap in _db().get_all(refs):
        product = snap.to_dict() if snap.exists else None
        if not product or not product.get("active"):
            raise https_fn.HttpsError(Code.FAILED_PRECONDITION,
                                      "An item in your cart is no longer available.")
        qty = quantities[snap.id]
        if int(product.get("stock", 0)) < qty:
            raise https_fn.HttpsError(Code.FAILED_PRECONDITION,
                                      f"{product.get('name', 'An item')} is out of stock.")
        price = int(product["priceMinor"])
        item_currency = product.get("currency", "USD")
        if currency and item_currency != currency:
            raise _invalid("All items must be priced in the same currency.")
        currency = item_currency
        total += price * qty
        lines.append({"productId": snap.id, "name": str(product.get("name", ""))[:127],
                      "quantity": qty, "unitPriceMinor": price})

    count = sum(quantities.values())
    merchant = MERCHANT_NAME.value
    return {
        "currency": currency,
        "amountMinor": total,
        "items": lines,
        "description": lines[0]["name"] if len(lines) == 1 else f"{count} items from {merchant}",
        "recipient": merchant,
        "paypal_items": [
            {"name": l["name"], "sku": l["productId"][:127], "quantity": str(l["quantity"]),
             "unit_amount": {"currency_code": currency, "value": _value(l["unitPriceMinor"])}}
            for l in lines
        ],
        "shipping": "GET_FROM_FILE",
        "payee": None,
    }


def _prepare_donation(data: dict[str, Any]) -> dict[str, Any]:
    campaign_id, amount = data.get("campaignId"), data.get("amountMinor")
    if not isinstance(campaign_id, str) or not campaign_id or not isinstance(amount, int):
        raise _invalid("Choose a campaign and amount.")
    snap = _db().collection("campaigns").document(campaign_id).get()
    campaign = snap.to_dict() if snap.exists else None
    if not campaign or not campaign.get("active"):
        raise https_fn.HttpsError(Code.FAILED_PRECONDITION, "This campaign is no longer active.")
    minimum = int(campaign.get("minAmountMinor", 100))
    maximum = int(campaign.get("maxAmountMinor", _MAX_DONATION_MINOR))
    if not minimum <= amount <= maximum:
        raise _invalid("This donation amount is outside the campaign's limits.")
    currency = campaign.get("currency", "USD")
    title = str(campaign.get("title", "Donation"))[:127]
    organization = str(campaign.get("organization", ""))
    payee_id = campaign.get("payeeMerchantId")
    merchant = MERCHANT_NAME.value
    return {
        "currency": currency,
        "amountMinor": amount,
        "items": [],
        "campaignId": campaign_id,
        "campaignTitle": title,
        "description": f"Donation · {title}",
        "recipient": organization if payee_id else f"{merchant} for {organization}",
        "paypal_items": [{"name": title, "quantity": "1", "category": "DONATION",
                          "unit_amount": {"currency_code": currency, "value": _value(amount)}}],
        "shipping": "NO_SHIPPING",
        "payee": {"merchant_id": payee_id} if payee_id else None,
    }


@https_fn.on_call(secrets=_SECRETS)
def create_paypal_order(req: https_fn.CallableRequest) -> dict[str, Any]:
    uid = _uid(req)
    data = req.data if isinstance(req.data, dict) else {}
    kind, key = data.get("kind"), data.get("idempotencyKey")
    if kind not in _COLLECTIONS or not isinstance(key, str) or not _KEY_PATTERN.match(key):
        raise _invalid("Invalid checkout request.")

    _rate_limit(uid, "create")
    fingerprint = _request_fingerprint(kind, data)
    ref = _record_ref(uid, kind, key)
    existing = ref.get()
    if existing.exists:
        record = existing.to_dict()
        if record.get("requestHash") not in (None, fingerprint):
            raise _invalid("This checkout request does not match the original order.")
        # Network retry with the same key: return the existing order.
        return _session(key, kind, record)

    order = _prepare_shopping(data) if kind == "shopping" else _prepare_donation(data)
    currency = order["currency"]
    if currency in _UNSUPPORTED_CURRENCIES:
        raise https_fn.HttpsError(Code.FAILED_PRECONDITION, f"{currency} is not supported.")

    return_url, cancel_url = _return_urls()
    unit: dict[str, Any] = {
        "reference_id": key,
        "custom_id": f"{uid}|{kind}|{key}",
        "description": order["description"][:127],
        "amount": {
            "currency_code": currency,
            "value": _value(order["amountMinor"]),
            "breakdown": {"item_total": {"currency_code": currency,
                                         "value": _value(order["amountMinor"])}},
        },
        "items": order["paypal_items"],
    }
    if order["payee"]:
        unit["payee"] = order["payee"]
    body = {
        "intent": "CAPTURE",
        "purchase_units": [unit],
        "payment_source": {"paypal": {"experience_context": {
            "brand_name": MERCHANT_NAME.value[:127],
            "user_action": "PAY_NOW",
            "shipping_preference": order["shipping"],
            "return_url": return_url,
            "cancel_url": cancel_url,
        }}},
    }

    try:
        created = _paypal().create_order(body, request_id=f"create-{key}")
    except PayPalError as e:
        raise _paypal_failure(e, "start checkout") from e

    record = {
        "kind": kind,
        "status": "CREATED",
        "amountMinor": order["amountMinor"],
        "currency": currency,
        "description": order["description"],
        "recipient": order["recipient"],
        "items": order["items"],
        "campaignId": order.get("campaignId"),
        "campaignTitle": order.get("campaignTitle"),
        "paypalOrderId": created.get("id"),
        "approveUrl": approve_link(created),
        "requestHash": fingerprint,
        "createdAt": firestore.SERVER_TIMESTAMP,
    }
    ref.set(record)
    return _session(key, kind, record)


def _apply_capture(uid: str, kind: str, record_id: str, capture_status: str,
                   capture_id: str | None, reason: str | None = None) -> str:
    """Moves a record to the status PayPal reported, exactly once.

    Shared by the capture call and the webhook so whichever arrives first
    applies the side effects (stock, campaign totals, activity,
    notification) and the other becomes a no-op.
    """
    status = {"COMPLETED": "COMPLETED", "PENDING": "PENDING"}.get(capture_status, "FAILED")
    ref = _record_ref(uid, kind, record_id)
    db = _db()

    @firestore.transactional
    def transition(tx) -> tuple[str, dict[str, Any] | None]:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            return "MISSING", None
        record = snap.to_dict()
        current = record.get("status")
        if current == status or current in _FINAL:
            return current, None
        update: dict[str, Any] = {"status": status, "updatedAt": firestore.SERVER_TIMESTAMP}
        if capture_id:
            update["captureId"] = capture_id
        if status == "COMPLETED":
            update["completedAt"] = firestore.SERVER_TIMESTAMP
            if kind == "shopping":
                for item in record.get("items", []):
                    tx.update(db.collection("catalog_products").document(item["productId"]),
                              {"stock": firestore.Increment(-int(item["quantity"]))})
            elif record.get("campaignId"):
                tx.update(db.collection("campaigns").document(record["campaignId"]), {
                    "raisedMinor": firestore.Increment(int(record["amountMinor"])),
                    "donorCount": firestore.Increment(1),
                })
        if status == "FAILED":
            update["failureReason"] = reason or "PayPal declined this payment. You have not been charged."
        tx.update(ref, update)
        return status, record

    new_status, record = transition(db.transaction())
    if record is None:
        return new_status

    activity_type = "shopping_order" if kind == "shopping" else "donation"
    _write_activity(uid, activity_type, record_id, new_status, record, kind)
    if new_status == "COMPLETED":
        _notify(uid, "notifyPayments", "Payment confirmed",
                f"PayPal confirmed your payment for {record.get('description', 'your order')}.")
    elif new_status == "FAILED":
        _notify(uid, "notifyPayments", "Payment not completed",
                "PayPal could not complete your payment. You have not been charged.")
    return new_status


def _write_activity(uid: str, activity_type: str, record_id: str, status: str,
                    record: dict[str, Any], kind: str, subtitle: str | None = None) -> None:
    activity_status = {"COMPLETED": "completed", "REFUNDED": "completed", "FAILED": "failed",
                       "CANCELLED": "cancelled"}.get(status, "pending")
    default_subtitle = {"COMPLETED": "Paid with PayPal", "PENDING": "PayPal is processing",
                        "FAILED": "Declined by PayPal"}.get(status, status.title())
    _db().collection("users").document(uid).collection("activity").document(
        f"{activity_type}_{record_id}").set({
            "type": activity_type,
            "status": activity_status,
            "title": record.get("campaignTitle") or record.get("description", ""),
            "subtitle": subtitle or default_subtitle,
            "amountMinor": record.get("amountMinor"),
            "currency": record.get("currency"),
            "route": f"/payments/{kind}/{record_id}",
            "source": "server",
            "createdAt": record.get("createdAt") or firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        })


def _claim_capture(ref) -> tuple[str, dict[str, Any] | None]:
    """Atomically moves an order to CAPTURE_PENDING so only one request at a
    time can call PayPal capture for it."""

    @firestore.transactional
    def claim(tx) -> tuple[str, dict[str, Any] | None]:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            return "MISSING", None
        record = snap.to_dict()
        status = record.get("status")
        now = datetime.now(timezone.utc)
        if status == "CAPTURE_PENDING":
            started = record.get("captureStartedAt")
            if started and now - started < timedelta(seconds=_CAPTURE_LOCK_SECONDS):
                return "BUSY", record
        elif status not in ("CREATED", "APPROVED"):
            return "DONE", record
        tx.update(ref, {"status": "CAPTURE_PENDING", "captureStartedAt": now})
        return "CLAIMED", record

    return claim(_db().transaction())


def _release_capture(ref, status: str) -> None:
    @firestore.transactional
    def release(tx) -> None:
        snap = ref.get(transaction=tx)
        if snap.exists and snap.get("status") == "CAPTURE_PENDING":
            tx.update(ref, {"status": status})

    release(_db().transaction())


@https_fn.on_call(secrets=_SECRETS)
def capture_paypal_order(req: https_fn.CallableRequest) -> dict[str, Any]:
    uid = _uid(req)
    data = req.data if isinstance(req.data, dict) else {}
    kind, record_id = data.get("kind"), data.get("recordId")
    _rate_limit(uid, "capture")
    ref = _record_ref(uid, kind, record_id)
    claim, record = _claim_capture(ref)
    if claim != "CLAIMED":
        if record is None:
            raise https_fn.HttpsError(Code.NOT_FOUND, "This order could not be found.")
        return {"status": record.get("status"), "captureId": record.get("captureId")}

    client = _paypal()
    order_id = record["paypalOrderId"]
    try:
        result = client.capture_order(order_id, request_id=f"capture-{record_id}")
    except PayPalError as e:
        if e.name == "ORDER_NOT_APPROVED":
            _release_capture(ref, "CREATED")
            return {"status": "CREATED"}
        if e.name == "ORDER_ALREADY_CAPTURED":
            result = client.get_order(order_id)
        elif e.name in ("INSTRUMENT_DECLINED", "PAYER_ACTION_REQUIRED", "TRANSACTION_REFUSED"):
            status = _apply_capture(uid, kind, record_id, "DECLINED", None,
                                    "PayPal declined the payment method. You have not been charged.")
            return {"status": status}
        else:
            _release_capture(ref, "APPROVED")
            raise _paypal_failure(e, "confirm the payment") from e
    except requests.RequestException:
        # The capture may have succeeded even though the response was lost,
        # so ask PayPal before allowing another attempt.
        try:
            result = client.get_order(order_id)
        except (PayPalError, requests.RequestException):
            return {"status": "CAPTURE_PENDING"}

    capture = first_capture(result)
    if capture is None:
        status = "APPROVED" if result.get("status") == "APPROVED" else "CREATED"
        _release_capture(ref, status)
        return {"status": status}
    amount = capture.get("amount") or {}
    if amount.get("value") != _value(int(record["amountMinor"])) or \
            amount.get("currency_code") != record["currency"]:
        logger.error("Captured amount does not match order", record_id=record_id)
        status = _apply_capture(uid, kind, record_id, "FAILED", capture.get("id"),
                                "The captured amount did not match the order. Contact support.")
        return {"status": status}
    status = _apply_capture(uid, kind, record_id, capture.get("status", ""), capture.get("id"))
    return {"status": status, "captureId": capture.get("id")}


@https_fn.on_call()
def cancel_paypal_order(req: https_fn.CallableRequest) -> dict[str, Any]:
    uid = _uid(req)
    _rate_limit(uid, "cancel")
    data = req.data if isinstance(req.data, dict) else {}
    ref = _record_ref(uid, data.get("kind"), data.get("recordId"))
    db = _db()

    @firestore.transactional
    def cancel(tx) -> str:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            return "MISSING"
        status = snap.get("status")
        # Only an order the buyer never approved can be cancelled here; an
        # unapproved PayPal order expires on its own and cannot be charged.
        if status != "CREATED":
            return status
        tx.update(ref, {"status": "CANCELLED", "updatedAt": firestore.SERVER_TIMESTAMP})
        return "CANCELLED"

    return {"status": cancel(db.transaction())}


def _claim_refund(ref) -> tuple[bool, dict[str, Any] | None]:
    """Claims the refund in a transaction so two concurrent calls cannot both
    reach PayPal. Returns whether this call won the claim."""

    @firestore.transactional
    def claim(tx) -> tuple[bool, dict[str, Any] | None]:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            return False, None
        record = snap.to_dict()
        if record.get("refundStatus") is not None:
            return False, record
        tx.update(ref, {"refundStatus": "REQUESTED"})
        return True, record

    return claim(_db().transaction())


@https_fn.on_call(secrets=_SECRETS)
def refund_paypal_order(req: https_fn.CallableRequest) -> dict[str, Any]:
    uid = _uid(req)
    data = req.data if isinstance(req.data, dict) else {}
    record_id = data.get("recordId")
    reason = str(data.get("reason") or "")[:255]
    _rate_limit(uid, "refund")
    ref = _record_ref(uid, "shopping", record_id)
    claimed, record = _claim_refund(ref)
    if record is None:
        raise https_fn.HttpsError(Code.NOT_FOUND, "This order could not be found.")
    if not claimed:
        return {"status": record.get("refundStatus")}
    if record.get("status") != "COMPLETED" or not record.get("captureId"):
        ref.update({"refundStatus": firestore.DELETE_FIELD})
        raise https_fn.HttpsError(Code.FAILED_PRECONDITION,
                                  "Only paid orders can be refunded.")
    completed_at = record.get("completedAt")
    window = timedelta(days=REFUND_WINDOW_DAYS.value)
    if completed_at is None or datetime.now(timezone.utc) - completed_at > window:
        ref.update({"refundStatus": firestore.DELETE_FIELD})
        raise https_fn.HttpsError(
            Code.FAILED_PRECONDITION,
            f"This order is outside the {REFUND_WINDOW_DAYS.value}-day refund window.")

    try:
        refund = _paypal().refund_capture(
            record["captureId"],
            {"note_to_payer": reason or "Refund requested in FLOWMINT",
             "custom_id": f"{uid}|shopping|{record_id}"},
            request_id=f"refund-{record_id}",
        )
    except PayPalError as e:
        ref.update({"refundStatus": firestore.DELETE_FIELD})
        raise _paypal_failure(e, "process the refund") from e
    except requests.RequestException:
        # Outcome unknown: keep the claim. The PayPal-Request-Id makes a later
        # retry return the original refund rather than issue a second one.
        return {"status": "PENDING"}

    refund_status = refund.get("status", "PENDING")
    update: dict[str, Any] = {"refundStatus": refund_status, "refundId": refund.get("id"),
                              "updatedAt": firestore.SERVER_TIMESTAMP}
    if refund_status == "COMPLETED":
        update.update({"status": "REFUNDED", "refundedMinor": int(record["amountMinor"])})
    ref.update(update)
    _write_activity(uid, "refund", record_id, "REFUNDED" if refund_status == "COMPLETED" else "PENDING",
                    record, "shopping",
                    subtitle="Refunded by PayPal" if refund_status == "COMPLETED"
                    else "PayPal is processing the refund")
    if refund_status == "COMPLETED":
        _notify(uid, "notifyActivity", "Refund completed",
                f"PayPal refunded your order: {record.get('description', '')}.")
    return {"status": refund_status}


def _parse_custom_id(resource: dict[str, Any]) -> tuple[str, str, str] | None:
    parts = str(resource.get("custom_id") or "").split("|")
    if len(parts) != 3 or not parts[0] or parts[1] not in _COLLECTIONS:
        return None
    if not _KEY_PATTERN.match(parts[2]):
        return None
    return parts[0], parts[1], parts[2]


@https_fn.on_request(secrets=_SECRETS)
def paypal_webhook(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return https_fn.Response(status=405)
    webhook_id = PAYPAL_WEBHOOK_ID.value
    if not webhook_id:
        logger.error("PAYPAL_WEBHOOK_ID is not configured; rejecting webhook")
        return https_fn.Response(status=503)
    event = req.get_json(silent=True) or {}
    try:
        verified = _paypal().verify_webhook(dict(req.headers), event, webhook_id)
    except (PayPalError, https_fn.HttpsError):
        verified = False
    if not verified:
        return https_fn.Response(status=400)

    event_type = event.get("event_type", "")
    resource = event.get("resource") or {}
    target = _parse_custom_id(resource)
    if target is None:
        return https_fn.Response(status=200)
    uid, kind, record_id = target

    if event_type in ("PAYMENT.CAPTURE.COMPLETED", "PAYMENT.CAPTURE.PENDING",
                      "PAYMENT.CAPTURE.DENIED", "PAYMENT.CAPTURE.DECLINED"):
        _apply_capture(uid, kind, record_id, resource.get("status", ""), resource.get("id"))
    elif event_type in ("PAYMENT.CAPTURE.REFUNDED", "PAYMENT.CAPTURE.REVERSED"):
        ref = _record_ref(uid, kind, record_id)
        snap = ref.get()
        if snap.exists:
            record = snap.to_dict()
            full = resource.get("status") in ("REFUNDED", "REVERSED")
            ref.update({
                "status": "REFUNDED" if full else "PARTIALLY_REFUNDED",
                "refundStatus": "COMPLETED",
                "refundedMinor": int(record["amountMinor"]) if full else record.get("refundedMinor", 0),
                "updatedAt": firestore.SERVER_TIMESTAMP,
            })
            if kind == "shopping":
                _write_activity(uid, "refund", record_id, "REFUNDED", record, kind,
                                subtitle="Refunded by PayPal")
    return https_fn.Response(status=200)


def _notify(uid: str, preference: str, title: str, body: str) -> None:
    """Sends a push notification if the user enabled this category."""
    user_ref = _db().collection("users").document(uid)
    user = user_ref.get().to_dict() or {}
    tokens = [t for t in user.get("fcmTokens", []) if isinstance(t, str)]
    if not tokens or not user.get(preference, True):
        return
    try:
        result = messaging.send_each_for_multicast(messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
        ))
    except Exception as e:  # Notifications must never break a payment flow.
        logger.warn("Push notification failed", error=type(e).__name__)
        return
    stale = [tokens[i] for i, r in enumerate(result.responses)
             if not r.success and isinstance(r.exception, messaging.UnregisteredError)]
    if stale:
        user_ref.update({"fcmTokens": firestore.ArrayRemove(stale)})


def _add_months(d: datetime, months: int) -> datetime:
    month_index = d.month - 1 + months
    year, month = d.year + month_index // 12, month_index % 12 + 1
    day = min(d.day, calendar.monthrange(year, month)[1])
    return d.replace(year=year, month=month, day=day)


def _advance(d: datetime, frequency: str) -> datetime:
    if frequency == "weekly":
        return d + timedelta(days=7)
    return _add_months(d, {"quarterly": 3, "yearly": 12}.get(frequency, 1))


@scheduler_fn.on_schedule(schedule="every day 09:00", timezone=scheduler_fn.Timezone("Asia/Kolkata"))
def renewal_reminders(event: scheduler_fn.ScheduledEvent) -> None:
    """Rolls past renewal dates forward and reminds users 3 days ahead."""
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=1)
    horizon = now + timedelta(days=3)
    query = _db().collection_group("subscriptions").where(
        filter=FieldFilter("nextRenewal", "<=", horizon))
    for doc in query.stream():
        sub = doc.to_dict()
        if not sub.get("active", True):
            continue
        renewal = sub.get("nextRenewal")
        if renewal is None:
            continue
        rolled = renewal
        for _ in range(520):
            if rolled >= start:
                break
            rolled = _advance(rolled, sub.get("frequency", "monthly"))
        if rolled != renewal:
            doc.reference.update({"nextRenewal": rolled})
        key = rolled.date().isoformat()
        if rolled > horizon or not sub.get("reminders", True) or sub.get("lastReminderFor") == key:
            continue
        uid = doc.reference.parent.parent.id
        _notify(uid, "notifyRenewals", f"{sub.get('name', 'A subscription')} renews soon",
                f"Renews on {rolled.strftime('%d %b')}. Review it in FLOWMINT if you no longer need it.")
        doc.reference.update({"lastReminderFor": key})
