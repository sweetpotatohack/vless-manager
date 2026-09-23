from __future__ import annotations

from fastapi import Cookie, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.config import SECRET_KEY, SESSION_COOKIE
from app.database import get_db
from app.models import AdminUser
from itsdangerous import BadSignature, URLSafeSerializer

serializer = URLSafeSerializer(SECRET_KEY, salt="vless-panel-admin")


def create_session_token(admin_id: int) -> str:
    return serializer.dumps({"admin_id": admin_id})


def read_session_token(token: str) -> int | None:
    try:
        data = serializer.loads(token)
        return int(data.get("admin_id"))
    except (BadSignature, TypeError, ValueError):
        return None


def get_current_admin(
    request: Request,
    db: Session = Depends(get_db),
    session: str | None = Cookie(default=None, alias=SESSION_COOKIE),
) -> AdminUser:
    if not session:
        raise HTTPException(status_code=401, detail="Not authenticated")
    admin_id = read_session_token(session)
    if not admin_id:
        raise HTTPException(status_code=401, detail="Invalid session")
    admin = db.get(AdminUser, admin_id)
    if not admin:
        raise HTTPException(status_code=401, detail="Admin not found")
    return admin


def get_optional_admin(
    session: str | None = Cookie(default=None, alias=SESSION_COOKIE),
    db: Session = Depends(get_db),
) -> AdminUser | None:
    if not session:
        return None
    admin_id = read_session_token(session)
    if not admin_id:
        return None
    return db.get(AdminUser, admin_id)
