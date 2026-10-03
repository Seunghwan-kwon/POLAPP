import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt


PBKDF2_ITERATIONS = 210_000


def hash_matching_code(code: str, salt: bytes | None = None) -> str:
    actual_salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        code.encode("utf-8"),
        actual_salt,
        PBKDF2_ITERATIONS,
    )
    return f"{actual_salt.hex()}:{digest.hex()}"


def verify_matching_code(code: str, encoded: str) -> bool:
    try:
        salt_hex, expected_hex = encoded.split(":", 1)
        actual = hash_matching_code(code, bytes.fromhex(salt_hex)).split(":", 1)[1]
        return hmac.compare_digest(actual, expected_hex)
    except (ValueError, TypeError):
        return False


def issue_token(officer: dict[str, Any], secret: str) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": str(officer["id"]),
            "officerId": officer["code"],
            "role": officer["role"],
            "iat": now,
            "exp": now + timedelta(hours=8),
        },
        secret,
        algorithm="HS256",
    )


def decode_token(token: str, secret: str) -> dict[str, Any] | None:
    try:
        return jwt.decode(token, secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None


def development_secret(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if value:
        return value
    return f"polapp-local-only-{name.lower()}-change-before-sharing"
