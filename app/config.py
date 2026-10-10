"""Client configuration: server URL with localhost default, persisted locally.

IPv6-aware: bare IPv6 hosts (e.g. ::1) are bracketed automatically, so
http://::1:8000 and http://[::1]:8000 both work.
"""

import ipaddress
import json
import os

DEFAULT_SERVER_URL = "http://localhost:8000"

_CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".script-maker-mac")
_CONFIG_PATH = os.path.join(_CONFIG_DIR, "config.json")


def _bracket_ipv6(hostport: str) -> str:
    """Wrap a bare IPv6 host in brackets. Already-bracketed, IPv4 and hostnames pass through.

    Bare IPv6 with a port is ambiguous (``::1:8000`` is also a valid address),
    so a trailing :port wins when the head is a valid IPv6 address — that is
    the natural reading in a server-URL field. Bracketed form is unambiguous;
    prefer it.
    """
    if hostport.startswith("["):
        return hostport
    if hostport.count(":") <= 1:
        return hostport  # hostname, IPv4, or host:port
    # Port-first: head must be valid IPv6 and tail a valid port.
    head, _, tail = hostport.rpartition(":")
    if tail.isdigit() and 0 < int(tail) <= 65535:
        try:
            ipaddress.IPv6Address(head)
            return f"[{head}]:{tail}"
        except ipaddress.AddressValueError:
            pass
    # Whole thing as an IPv6 address (no port).
    try:
        ipaddress.IPv6Address(hostport)
        return f"[{hostport}]"
    except ipaddress.AddressValueError:
        pass
    raise ValueError(f"Could not parse {hostport!r} as an IPv6 address with optional port.")


def normalize_server_url(url: str) -> str:
    """Validate and normalize a server URL. Fail-loud on bad input."""
    url = (url or "").strip().rstrip("/")
    if not url:
        raise ValueError("Server URL must not be empty.")
    if "://" not in url:
        raise ValueError(f"Server URL must include a scheme (http:// or https://), got {url!r}.")
    scheme, rest = url.split("://", 1)
    if scheme not in ("http", "https"):
        raise ValueError(f"Server URL scheme must be http or https, got {scheme!r}.")
    if not rest:
        raise ValueError("Server URL must include a host.")
    return f"{scheme}://{_bracket_ipv6(rest)}"


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
    url = normalize_server_url(url)
    os.makedirs(_CONFIG_DIR, exist_ok=True)
    with open(_CONFIG_PATH, "w") as f:
        json.dump({"server_url": url}, f)
    return url
