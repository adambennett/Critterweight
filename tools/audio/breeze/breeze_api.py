"""Shared Breeze HTTPS transport. Identifies this tool; never retries requests."""

import json
import urllib.error
import urllib.request
from decimal import Decimal, InvalidOperation

from configure_key import validate_key


API_BASE = "https://api.breeze.blue"
USER_AGENT = "Critterweight-VoiceTools/1.0"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Do not forward the credential or repeat a paid POST after a redirect.
        return None


def request_bytes(path, api_key, payload=None, accept="application/json"):
    api_key = validate_key(api_key)
    if not path.startswith("/v1/"):
        raise ValueError("Expected a Breeze /v1/ API path.")
    headers = {"xi-api-key": api_key, "Accept": accept, "User-Agent": USER_AGENT}
    body = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(API_BASE + path, data=body, headers=headers,
                                     method="POST" if body is not None else "GET")
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=120) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        try:
            body = exc.read(4096).decode("utf-8", errors="replace")
        except OSError:
            body = ""
        detail = ""
        try:
            parsed = json.loads(body)
            if isinstance(parsed, dict):
                code = parsed.get("code") or parsed.get("error_code")
                message = parsed.get("detail") or parsed.get("error")
                detail = ": ".join(str(x) for x in (code, message) if x)
        except ValueError:
            detail = " ".join(body.split())
        detail = detail.replace(api_key, "[redacted]")[:500]
        suffix = " ({})".format(detail) if detail else ""
        raise RuntimeError(
            "Breeze returned HTTP {}{}. No automatic retry was made. "
            "Check the provider request log before retrying generation.".format(exc.code, suffix)) from None
    except (urllib.error.URLError, OSError) as exc:
        reason = str(getattr(exc, "reason", exc)).replace(api_key, "[redacted]")[:300]
        raise RuntimeError(
            "Breeze request outcome may be ambiguous ({}). No automatic retry was made. "
            "Check the provider request log before retrying generation.".format(reason)) from None


def request_json(path, api_key, payload=None):
    try:
        return json.loads(request_bytes(path, api_key, payload).decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise RuntimeError("Breeze returned invalid JSON; no automatic retry was made.") from None


def remaining_key_credits(api_key, require_limit=False):
    """Read fresh counters, never reserve credits or alter an owner's limit."""
    data = request_json("/v1/api-keys/current", api_key)
    current = data.get("api_key") if isinstance(data, dict) else None
    if not isinstance(current, dict) or "credit_remaining" not in current or "credit_limit" not in current:
        raise RuntimeError("Breeze did not return usable key-budget counters; no generation was started.")
    if current.get("status") not in ("active", "expiring"):
        raise RuntimeError("The Breeze key is not active; ask the owner to check it.")
    if current["credit_limit"] is None:
        if require_limit:
            raise RuntimeError("--use-key-budget requires a finite provider key limit. Ask the owner to set one; no generation was started.")
        return None
    try:
        remaining = Decimal(str(current["credit_remaining"]))
        limit = Decimal(str(current["credit_limit"]))
    except InvalidOperation:
        raise RuntimeError("Breeze returned invalid key-budget counters.") from None
    if not remaining.is_finite() or remaining < 0 or not limit.is_finite() or limit < 0 or remaining > limit:
        raise RuntimeError("Breeze returned invalid key-budget counters.")
    return remaining

