#!/usr/bin/env python3
"""One-time Pixiv login helper for the random wallpaper script.

Get a refresh token (needs your Pixiv account, done once):

    1. python3 pixiv-auth.py get-url
       -> opens the Pixiv login page in your browser and prints the URL
    2. Log in. The browser then lands on a page like
          https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback?state=...&code=...
       Copy the value of the "code" parameter (it expires fast - be quick).
    3. python3 pixiv-auth.py exchange CODE
       -> prints your tokens and saves the refresh token to
          ~/.config/pixiv/refresh-token  (chmod 600)

Optional check afterwards:  python3 pixiv-auth.py refresh <REFRESH_TOKEN>
"""

import base64
import hashlib
import json
import os
import secrets
import sys
import urllib.parse
import urllib.request

USER_AGENT = "PixivAndroidApp/5.0.234 (Android 11; Pixel 5)"
REDIRECT_URI = "https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback"
LOGIN_URL = "https://app-api.pixiv.net/web/v1/login"
AUTH_TOKEN_URL = "https://oauth.secure.pixiv.net/auth/token"

# Built-in defaults for the public for_android app pair. Override them by putting
# PIXIV_CLIENT_ID / PIXIV_CLIENT_SECRET in ~/.config/pixiv/config, the same
# sourceable KEY="value" file the random script and the shell read for
# PIXIV_ALLOW_NSFW and PIXIV_TAGS. An override that is present but blank is
# ignored, so a half-edited line falls back here rather than breaking login.
DEFAULT_CLIENT_ID = "MOBrBDS8blbauoSck0ZfDbtuzpyT"
DEFAULT_CLIENT_SECRET = "lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj"


def config_file() -> str:
    xdg = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    return os.path.join(xdg, "pixiv", "config")


def config_value(key: str, fallback: str = "") -> str:
    """Last assignment wins, quotes stripped, comments skipped.

    Mirrors get_value() in pixiv_nsfw.sh and _pixivConfigValue() in the shell's
    OnlineWallpapers.qml, so all three agree on which value is in effect.
    """
    path = config_file()
    if not os.path.isfile(path):
        return fallback
    value = None
    with open(path, encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith(key + "="):
                value = line[len(key) + 1:].strip().strip("\"'")
    if not value:
        return fallback
    return value


CLIENT_ID = config_value("PIXIV_CLIENT_ID", DEFAULT_CLIENT_ID)
CLIENT_SECRET = config_value("PIXIV_CLIENT_SECRET", DEFAULT_CLIENT_SECRET)


def s256(data: bytes) -> str:
    return base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode("ascii")


def token_file() -> str:
    xdg = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    return os.path.join(xdg, "pixiv", "refresh-token")


def post_form(url: str, data: dict) -> dict:
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def print_tokens(resp: dict) -> str:
    refresh = resp.get("refresh_token")
    if not refresh:
        print("error:", json.dumps(resp, indent=2))
        sys.exit(1)
    print("access_token:", resp.get("access_token"))
    print("refresh_token:", refresh)
    print("expires_in:", resp.get("expires_in", 0))
    return refresh


def save_token(refresh: str) -> None:
    path = token_file()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(refresh + "\n")
    os.chmod(path, 0o600)
    print("saved refresh token to", path)


def get_url() -> None:
    verifier = secrets.token_urlsafe(32)
    challenge = s256(verifier.encode("ascii"))
    verifier_path = os.path.join(
        os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
        "pixiv-auth-verifier",
    )
    os.makedirs(os.path.dirname(verifier_path), exist_ok=True)
    with open(verifier_path, "w") as fh:
        fh.write(verifier + "\n")
    os.chmod(verifier_path, 0o600)
    params = urllib.parse.urlencode(
        {
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "client": "pixiv-android",
        }
    )
    url = f"{LOGIN_URL}?{params}"
    print("Open this URL in your browser and log in:", url)
    try:
        import subprocess
        subprocess.Popen(
            ["xdg-open", url],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def exchange(code: str) -> None:
    verifier_path = os.path.join(
        os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
        "pixiv-auth-verifier",
    )
    with open(verifier_path) as fh:
        verifier = fh.read().strip()
    resp = post_form(
        AUTH_TOKEN_URL,
        {
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "include_policy": "true",
            "redirect_uri": REDIRECT_URI,
        },
    )
    refresh = print_tokens(resp)
    save_token(refresh)


def refresh_token(refresh: str) -> None:
    resp = post_form(
        AUTH_TOKEN_URL,
        {
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "grant_type": "refresh_token",
            "include_policy": "true",
            "refresh_token": refresh,
        },
    )
    refresh = print_tokens(resp)
    save_token(refresh)


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "get-url":
        get_url()
    elif cmd == "exchange" and len(sys.argv) > 2:
        exchange(sys.argv[2])
    elif cmd == "refresh" and len(sys.argv) > 2:
        refresh_token(sys.argv[2])
    else:
        print(__doc__)


if __name__ == "__main__":
    main()