"""Client configuration: server URL with localhost default, persisted locally."""

import json
import os

DEFAULT_SERVER_URL = "http://localhost:8000"

_CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".script-maker-mac")
_CONFIG_PATH = os.path.join(_CONFIG_DIR, "config.json")


def get_server_url() -> str:
    """Return the configured server URL, defaulting to localhost."""
    try:
        with open(_CONFIG_PATH) as f:
            url = json.load(f).get("server_url", "").strip()
            if url:
                return url.rstrip("/")
    except (OSError, ValueError):
        pass
    return DEFAULT_SERVER_URL


def set_server_url(url: str) -> str:
    """Persist the server URL. Returns the normalized URL. Fail-loud on bad input."""
    url = (url or "").strip().rstrip("/")
    if not url:
        raise ValueError("Server URL must not be empty.")
    if not url.startswith(("http://", "https://")):
        raise ValueError(f"Server URL must start with http:// or https://, got {url!r}.")
    os.makedirs(_CONFIG_DIR, exist_ok=True)
    with open(_CONFIG_PATH, "w") as f:
        json.dump({"server_url": url}, f)
    return url
