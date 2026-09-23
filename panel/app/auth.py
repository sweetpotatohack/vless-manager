from __future__ import annotations

from passlib.context import CryptContext

from app.security import DUMMY_BCRYPT_HASH

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def verify_login_password(plain: str, hashed: str | None) -> bool:
    """Always run bcrypt when hash missing (mitigate user enumeration timing)."""
    target = hashed if hashed else DUMMY_BCRYPT_HASH
    return pwd_context.verify(plain, target) and bool(hashed)
