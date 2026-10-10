"""Script Maker for Mac — Streamlit thin client.

Same UX as the classic app. Every task goes over HTTP to the pipeline server;
nothing is imported from the pipeline directly.

Run: streamlit run app/main.py
"""

import streamlit as st

from api_client import PipelineClient, ServerUnreachable
from config import DEFAULT_SERVER_URL, get_server_url, set_server_url
from views.preferences import render_preferences

st.set_page_config(page_title="Script Maker", page_icon="assets/AppIcon.iconset/icon_32x32.png")

# ── Top: server connection ──────────────────────────────────────────────
client = PipelineClient(get_server_url())
connected = client.ping()

with st.sidebar:
    st.header("Script Maker")
    page = st.radio("Go to", ["Generate", "Preferences"], label_visibility="collapsed")
    st.divider()
    status = "🟢 Connected" if connected else "🔴 Offline"
    st.caption(f"{status} · `{client.base_url}`")
    if not connected:
        st.caption("UI works offline — generation needs the server.")

# ── Pages ───────────────────────────────────────────────────────────────
if page == "Preferences":
    render_preferences(client)
else:
    st.title("Script Maker")
    if not connected:
        st.warning(
            "Pipeline server not reachable at "
            f"`{client.base_url}`. Start the server (default `http://localhost:8000`) "
            "or update the Server URL in Preferences. The UI remains usable offline."
        )
    st.caption("Thin client — same UX, server-backed. Stage views plug in here as the port progresses.")
    # TODO(port): migrate stage views from ai-script-maker's app.py, replacing
    # direct agent imports with PipelineClient calls (run_stage / select /
    # start_job + SSE stream_events).
