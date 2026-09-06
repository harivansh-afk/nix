"""Verify Mixbridge user tokens and bound work in the single API worker."""

import threading
import time

import jwt
from fastapi import Header, HTTPException

ISSUER = "https://mixbridge.app"
AUDIENCE = "mixbridge-stream"
keys = jwt.PyJWKClient(f"{ISSUER}/api/stream-jwks", lifespan=300, timeout=5)
lock = threading.Lock()
traffic = {}
active_requests = 0


def unauthorized():
    return HTTPException(401, "Sign in to Mixbridge again", headers={"WWW-Authenticate": "Bearer"})


def verify_token(authorization):
    if not authorization or len(authorization) > 8192:
        raise unauthorized()
    scheme, separator, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not separator or not token:
        raise unauthorized()
    try:
        header = jwt.get_unverified_header(token)
        kid = header.get("kid")
        if (header.get("alg") != "RS256" or header.get("typ") != "at+jwt"
                or not isinstance(kid, str) or not 1 <= len(kid) <= 128):
            raise unauthorized()
        # Unknown key IDs never force an extra network fetch. Rotation follows
        # the five-minute public key cache instead of an attacker-controlled kid.
        matching = [key for key in keys.get_signing_keys() if key.key_id == kid]
        if (len(matching) != 1 or matching[0].algorithm_name != "RS256"
                or matching[0].key.key_size < 2048):
            raise unauthorized()
        claims = jwt.decode(
            token, matching[0].key, algorithms=["RS256"],
            issuer=ISSUER, audience=AUDIENCE, leeway=15,
            options={"require": ["iss", "aud", "sub", "iat", "exp", "scope"], "strict_aud": True},
        )
        subject = claims["sub"]
        if (claims["scope"] != "stream" or type(claims["iat"]) is not int
                or type(claims["exp"]) is not int
                or not 0 < claims["exp"] - claims["iat"] <= 300
                or not isinstance(subject, str) or not 1 <= len(subject) <= 256
                or not subject.startswith(("soundcloud:", "spotify:"))
                or not subject.partition(":")[2]):
            raise unauthorized()
        return subject
    except jwt.PyJWKClientConnectionError:
        raise HTTPException(503, "Sign-in verification is temporarily unavailable") from None
    except jwt.PyJWTError:
        raise unauthorized() from None


def require_user(authorization: str | None = Header(default=None)):
    global active_requests
    subject = verify_token(authorization)
    now = time.monotonic()
    with lock:
        for key in list(traffic):
            if traffic[key]["until"] <= now and traffic[key]["active"] == 0:
                del traffic[key]
        if subject not in traffic:
            if len(traffic) >= 10000:
                raise HTTPException(503, "API is busy; retry later")
            traffic[subject] = {"until": now + 60, "count": 0, "active": 0}
        bucket = traffic[subject]
        if bucket["until"] <= now:
            bucket.update(until=now + 60, count=0)
        if bucket["count"] >= 60:
            raise HTTPException(429, "User request limit reached", headers={"Retry-After": "60"})
        if bucket["active"] >= 2 or active_requests >= 4:
            raise HTTPException(429, "API is busy; retry shortly", headers={"Retry-After": "1"})
        bucket["count"] += 1
        bucket["active"] += 1
        active_requests += 1
    try:
        yield subject
    finally:
        with lock:
            bucket["active"] -= 1
            active_requests -= 1
