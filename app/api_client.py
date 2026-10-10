"""HTTP client for the Script Maker pipeline server.

Thin wrapper over the server API — the UI never imports the pipeline directly.
All long generations stream progress via Server-Sent Events.

API contract (server side):
    POST /sessions                      -> {"session_id": ...}
    POST /sessions/{id}/stages/{stage}  -> stage options (JSON)
    POST /sessions/{id}/select          -> {"selected": ...}, advances stage
    POST /sessions/{id}/jobs            -> {"job_id": ...} (202 Accepted)
    GET  /jobs/{job_id}                 -> {"status": ..., "progress": ...}
    GET  /sessions/{id}/events          -> SSE stream of substep events
"""

from typing import Callable, Dict, Iterator, Optional

import requests

# Stage names mirror the pipeline's six stages.
STAGE_VERIFY = "verify"
STAGE_CHARACTERS = "characters"
STAGE_DIALOGUE = "dialogue"
STAGE_SCENES = "scenes"
STAGE_STORYBOARD = "storyboard"
STAGE_RENDER = "render"

STAGES = [STAGE_VERIFY, STAGE_CHARACTERS, STAGE_DIALOGUE, STAGE_SCENES, STAGE_STORYBOARD, STAGE_RENDER]

DEFAULT_TIMEOUT = 30


class ServerError(RuntimeError):
    """The server answered with an error — surfaced loudly, never swallowed."""


class ServerUnreachable(RuntimeError):
    """No server at the configured URL — UI stays usable offline."""


class PipelineClient:
    def __init__(self, base_url: str, timeout: int = DEFAULT_TIMEOUT):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def _request(self, method: str, path: str, **kwargs) -> requests.Response:
        url = f"{self.base_url}{path}"
        try:
            resp = requests.request(method, url, timeout=self.timeout, **kwargs)
        except requests.ConnectionError as e:
            raise ServerUnreachable(
                f"Cannot reach pipeline server at {self.base_url}. "
                f"Start the server or update the Server URL in settings."
            ) from e
        if resp.status_code >= 400:
            raise ServerError(
                f"Server error {resp.status_code} on {method} {path}: {resp.text[:500]}"
            )
        return resp

    def ping(self) -> bool:
        """True if the server answers. Never raises — for status indicators."""
        try:
            self._request("GET", "/health")
            return True
        except (ServerUnreachable, ServerError):
            return False

    def create_session(self) -> str:
        resp = self._request("POST", "/sessions")
        session_id = resp.json().get("session_id")
        if not session_id:
            raise ServerError("Server created a session with no session_id.")
        return session_id

    def run_stage(self, session_id: str, stage: str, inputs: Optional[Dict] = None) -> Dict:
        if stage not in STAGES:
            raise ValueError(f"Unknown stage {stage!r}. Valid: {STAGES}")
        resp = self._request("POST", f"/sessions/{session_id}/stages/{stage}", json=inputs or {})
        return resp.json()

    def select(self, session_id: str, selection: Dict) -> Dict:
        resp = self._request("POST", f"/sessions/{session_id}/select", json=selection)
        return resp.json()

    def start_job(self, session_id: str, stage: str, inputs: Optional[Dict] = None) -> str:
        """Start an async generation job. Returns job_id for polling/SSE."""
        resp = self._request("POST", f"/sessions/{session_id}/jobs",
                             json={"stage": stage, **(inputs or {})})
        job_id = resp.json().get("job_id")
        if not job_id:
            raise ServerError("Server started a job with no job_id.")
        return job_id

    def job_status(self, job_id: str) -> Dict:
        resp = self._request("GET", f"/jobs/{job_id}")
        return resp.json()

    def stream_events(self, session_id: str,
                      on_event: Callable[[str, Dict], None]) -> None:
        """Consume the SSE substep stream until the server closes it."""
        url = f"{self.base_url}/sessions/{session_id}/events"
        try:
            with requests.get(url, stream=True, timeout=self.timeout) as resp:
                if resp.status_code >= 400:
                    raise ServerError(f"SSE stream failed: {resp.status_code}")
                event_name = "message"
                for line in resp.iter_lines(decode_unicode=True):
                    if not line:
                        continue
                    if line.startswith("event:"):
                        event_name = line[6:].strip()
                    elif line.startswith("data:"):
                        import json as _json
                        try:
                            on_event(event_name, _json.loads(line[5:].strip()))
                        except ValueError:
                            pass  # fail-loud happens server-side; skip malformed lines
        except requests.ConnectionError as e:
            raise ServerUnreachable(f"Lost connection to {self.base_url} mid-stream.") from e

    def stream_job(self, job_id: str) -> Iterator[Dict]:
        """Poll a job until it completes. Yields status dicts."""
        import time
        while True:
            status = self.job_status(job_id)
            yield status
            state = status.get("status")
            if state in ("done", "failed"):
                return
            time.sleep(1.0)
