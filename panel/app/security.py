from __future__ import annotations

import re
import secrets
import time
from collections import defaultdict
from threading import Lock

from fastapi import HTTPException, Request
from itsdangerous import BadSignature, URLSafeSerializer

from app.config import SECRET_KEY

CSRF_COOKIE = "vless_panel_csrf"
CSRF_MAX_AGE = 60 * 60 * 4
LOGIN_USERNAME_RE = re.compile(r"^[a-zA-Z0-9._-]{1,64}$")
MAX_PASSWORD_LEN = 128

_csrf_serializer = URLSafeSerializer(SECRET_KEY, salt="vless-panel-csrf")

# Precomputed bcrypt — constant-time path when user not found
DUMMY_BCRYPT_HASH = (
    "$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW"
)


class LoginRateLimiter:
    """In-memory limiter per IP (per uvicorn worker)."""

    def __init__(self, max_attempts: int = 10, window_seconds: int = 900) -> None:
        self.max_attempts = max_attempts
        self.window = window_seconds
        self._events: dict[str, list[float]] = defaultdict(list)
        self._lock = Lock()

    def _prune(self, ip: str, now: float) -> None:
        cutoff = now - self.window
        self._events[ip] = [t for t in self._events[ip] if t > cutoff]

    def is_blocked(self, ip: str) -> bool:
        now = time.monotonic()
        with self._lock:
            self._prune(ip, now)
            return len(self._events[ip]) >= self.max_attempts

    def record_failure(self, ip: str) -> None:
        now = time.monotonic()
        with self._lock:
            self._prune(ip, now)
            self._events[ip].append(now)

    def clear(self, ip: str) -> None:
        with self._lock:
            self._events.pop(ip, None)


login_rate_limiter = LoginRateLimiter()


def client_ip(request: Request) -> str:
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def normalize_login_username(raw: str) -> str | None:
    name = (raw or "").strip()
    if not name or len(name) > 64:
        return None
    if not LOGIN_USERNAME_RE.match(name):
        return None
    return name


def validate_password_length(password: str) -> bool:
    if not password:
        return False
    return len(password.encode("utf-8")) <= MAX_PASSWORD_LEN


def issue_csrf_token() -> str:
    return _csrf_serializer.dumps(
        {"n": secrets.token_hex(16), "t": int(time.time())},
    )


def parse_csrf_token(token: str) -> bool:
    try:
        data = _csrf_serializer.loads(token)
        issued = int(data.get("t", 0))
        return (time.time() - issued) <= CSRF_MAX_AGE
    except (BadSignature, TypeError, ValueError):
        return False


def ensure_csrf_request_state(request: Request) -> str:
    token = request.cookies.get(CSRF_COOKIE, "")
    if token and parse_csrf_token(token):
        request.state.csrf_token = token
        request.state.csrf_cookie_new = False
        return token
    token = issue_csrf_token()
    request.state.csrf_token = token
    request.state.csrf_cookie_new = True
    return token


def attach_csrf_cookie(response, request: Request, *, secure: bool) -> None:
    if not getattr(request.state, "csrf_cookie_new", False):
        return
    token = getattr(request.state, "csrf_token", "")
    if not token:
        return
    response.set_cookie(
        CSRF_COOKIE,
        token,
        httponly=True,
        samesite="lax",
        max_age=CSRF_MAX_AGE,
        secure=secure,
        path="/",
    )


def verify_csrf(request: Request, form_token: str) -> None:
    cookie = request.cookies.get(CSRF_COOKIE, "")
    form_token = (form_token or "").strip()
    if not cookie or not form_token:
        raise HTTPException(status_code=403, detail="CSRF token missing")
    if not parse_csrf_token(cookie):
        raise HTTPException(status_code=403, detail="CSRF token expired")
    if not secrets.compare_digest(cookie, form_token):
        raise HTTPException(status_code=403, detail="CSRF token invalid")


def apply_security_headers(response) -> None:
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src 'self' https://fonts.gstatic.com; "
        "img-src 'self' data:; "
        "form-action 'self'; "
        "frame-ancestors 'none'; "
        "base-uri 'self'"
    )
