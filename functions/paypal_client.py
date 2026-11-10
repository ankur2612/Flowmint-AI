"""Minimal PayPal REST client used by the FLOWMINT Cloud Functions.

Credentials are injected from Secret Manager at runtime and never logged.
"""

from __future__ import annotations

import threading
import time
from typing import Any

import requests

_BASE_URLS = {
    "sandbox": "https://api-m.sandbox.paypal.com",
    "live": "https://api-m.paypal.com",
}
_TIMEOUT_SECONDS = 20

_token_lock = threading.Lock()
_token_cache: dict[str, tuple[str, float]] = {}


class PayPalError(Exception):
    """A PayPal API error with the fields needed to decide how to respond."""

    def __init__(self, status: int, name: str, message: str, debug_id: str | None):
        super().__init__(f"{status} {name}: {message}")
        self.status = status
        self.name = name
        self.message = message
        self.debug_id = debug_id


class PayPalClient:
    def __init__(self, client_id: str, client_secret: str, environment: str = "sandbox"):
        if not client_id or not client_secret:
            raise ValueError("PayPal credentials are not configured")
        self._client_id = client_id
        self._client_secret = client_secret
        self._base = _BASE_URLS["live" if environment == "live" else "sandbox"]


    def _access_token(self) -> str:
        cache_key = f"{self._base}|{self._client_id}"
        with _token_lock:
            cached = _token_cache.get(cache_key)
            if cached and cached[1] - 60 > time.time():
                return cached[0]
            response = requests.post(
                f"{self._base}/v1/oauth2/token",
                auth=(self._client_id, self._client_secret),
                data={"grant_type": "client_credentials"},
                timeout=_TIMEOUT_SECONDS,
            )
            if response.status_code != 200:
                raise PayPalError(response.status_code, "AUTHENTICATION_FAILURE",
                                  "Could not authenticate with PayPal", None)
            body = response.json()
            token = body["access_token"]
            _token_cache[cache_key] = (token, time.time() + int(body.get("expires_in", 300)))
            return token


    def _request(self, method: str, path: str, *, json: Any = None,
                 request_id: str | None = None) -> dict[str, Any]:
        headers = {
            "Authorization": f"Bearer {self._access_token()}",
            "Content-Type": "application/json",
            # Return the full resource so status can be verified directly.
            "Prefer": "return=representation",
        }
        if request_id:
            # PayPal de-duplicates requests that reuse the same id.
            headers["PayPal-Request-Id"] = request_id
        response = requests.request(method, f"{self._base}{path}", json=json,
                                    headers=headers, timeout=_TIMEOUT_SECONDS)
        if response.status_code >= 400:
            try:
                body = response.json()
            except ValueError:
                body = {}
            details = body.get("details") or []
            issue = details[0].get("issue") if details else None
            raise PayPalError(
                response.status_code,
                issue or body.get("name") or "UNKNOWN_ERROR",
                body.get("message") or "PayPal request failed",
                body.get("debug_id"),
            )
        return response.json() if response.content else {}


    def create_order(self, body: dict[str, Any], request_id: str) -> dict[str, Any]:
        return self._request("POST", "/v2/checkout/orders", json=body, request_id=request_id)

    def get_order(self, order_id: str) -> dict[str, Any]:
        return self._request("GET", f"/v2/checkout/orders/{order_id}")

    def capture_order(self, order_id: str, request_id: str) -> dict[str, Any]:
        return self._request("POST", f"/v2/checkout/orders/{order_id}/capture",
                             json={}, request_id=request_id)


    def refund_capture(self, capture_id: str, body: dict[str, Any],
                       request_id: str) -> dict[str, Any]:
        return self._request("POST", f"/v2/payments/captures/{capture_id}/refund",
                             json=body, request_id=request_id)


    def verify_webhook(self, headers: dict[str, str], event: dict[str, Any],
                       webhook_id: str) -> bool:
        def header(name: str) -> str | None:
            return headers.get(name) or headers.get(name.lower())

        body = {
            "auth_algo": header("PAYPAL-AUTH-ALGO"),
            "cert_url": header("PAYPAL-CERT-URL"),
            "transmission_id": header("PAYPAL-TRANSMISSION-ID"),
            "transmission_sig": header("PAYPAL-TRANSMISSION-SIG"),
            "transmission_time": header("PAYPAL-TRANSMISSION-TIME"),
            "webhook_id": webhook_id,
            "webhook_event": event,
        }
        if not all(body.values()):
            return False
        result = self._request("POST", "/v1/notifications/verify-webhook-signature", json=body)
        return result.get("verification_status") == "SUCCESS"


def first_capture(order: dict[str, Any]) -> dict[str, Any] | None:
    """Returns the first capture of an order, if any."""
    for unit in order.get("purchase_units") or []:
        captures = (unit.get("payments") or {}).get("captures") or []
        if captures:
            return captures[0]
    return None


def approve_link(order: dict[str, Any]) -> str | None:
    for link in order.get("links") or []:
        if link.get("rel") in ("payer-action", "approve"):
            return link.get("href")
    return None
