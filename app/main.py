"""Script Maker for Mac — Streamlit thin client.

Same UX as the classic app. Every task goes over HTTP to the pipeline server;
nothing is imported from the pipeline directly.

Run: streamlit run app/main.py
"""

import streamlit as st

from api_client import PipelineClient, ServerUnreachable
from config import DEFAULT_SERVER_URL, get_server_url, set_server_url

st.set_page_config(page_title="Script Maker", page_icon="assets/AppIcon.iconset/icon_32x32.png")

# ── Top: server connection ──────────────────────────────────────────────
with st.sidebar:
    st.header("Server")
    server_url = st.text_input(
        "Pipeline server URL",
        value=get_server_url(),
        help="Where the pipeline server runs. Default is this Mac (localhost).",
    )
    if st.button("Save"):
        try:
            server_url = set_server_url(server_url)
            st.success(f"Server URL saved: {server_url}")
        except ValueError as e:
            st.error(str(e))

client = PipelineClient(server_url or DEFAULT_SERVER_URL)
connected = client.ping()

status = "🟢 Connected" if connected else "🔴 Offline — UI works, generation needs the server"
st.sidebar.caption(f"{status} · `{client.base_url}`")

# ── Main UX ─────────────────────────────────────────────────────────────
st.title("Script Maker")

if not connected:
    st.warning(
        "Pipeline server not reachable at "
        f"`{client.base_url}`. Start the server (default `http://localhost:8000`) "
        "or update the Server URL in the sidebar. The UI remains usable offline."
    )

st.caption("Thin client — same UX, server-backed. Stage views plug in here as the port progresses.")

# TODO(port): migrate stage views from ai-script-maker's app.py, replacing
# direct agent imports with PipelineClient calls (run_stage / select /
# start_job + SSE stream_events).
