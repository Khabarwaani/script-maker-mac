"""App-level Preferences — Mac-style settings for the thin client.

Pipeline settings (emotions, angles, etc.) live on the server. This page is
only about the app itself: connection, UI port, theme.
"""

import streamlit as st

from api_client import PipelineClient
from config import (
    DEFAULT_SERVER_URL,
    DEFAULT_UI_PORT,
    get_server_url,
    get_ui_port,
    normalize_server_url,
    set_server_url,
)


def render_preferences(client: PipelineClient) -> None:
    st.header("Preferences")

    with st.expander("Connection", expanded=True):
        server_url = st.text_input(
            "Pipeline server URL",
            value=get_server_url(),
            help="Where the pipeline server runs. Default is this Mac (localhost). "
                 "IPv6 addresses are accepted (e.g. http://[::1]:8000).",
        )
        col1, col2 = st.columns([1, 3])
        with col1:
            if st.button("Save", key="pref_save_url"):
                try:
                    saved = set_server_url(server_url)
                    st.success(f"Saved: {saved}")
                    st.rerun()
                except ValueError as e:
                    st.error(str(e))
        with col2:
            if st.button("Reset to default", key="pref_reset_url"):
                set_server_url(DEFAULT_SERVER_URL)
                st.rerun()
        st.caption(f"Current: `{get_server_url()}`")
        if st.button("Test connection", key="pref_test"):
            test_client = PipelineClient(get_server_url())
            if test_client.ping():
                st.success("Server reachable.")
            else:
                st.error("Server unreachable — check the URL and that the server is running.")

    with st.expander("App"):
        ui_port = st.number_input(
            "UI port",
            min_value=1,
            max_value=65535,
            value=get_ui_port(),
            help=f"Port for this app's own web UI. Default {DEFAULT_UI_PORT}. "
                 "Takes effect on next launch.",
        )
        st.caption("Theme and other display preferences follow the system / classic app theming.")
