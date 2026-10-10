# Script Maker for Mac

Thin-client UI for Script Maker. Same UX as always — only the data layer changed:
instead of importing the pipeline directly, every task goes over HTTP to the
pipeline server.

- **Works offline**: server defaults to `http://localhost:8000` — no internet needed.
- **Server URL** is a top-level setting — point it at a remote server anytime.
- **UX**: identical components, theming and Apple HIG compliance as the classic app.

## Architecture

```
script-maker-mac (this repo, public)     ai-script-maker (private)
┌─────────────────────────────┐         ┌──────────────────────────┐
│ Streamlit UI (thin client)  │  HTTP   │ Pipeline server (API)    │
│ app/main.py                 │ ◄─────► │ sessions / stages / jobs │
│ app/api_client.py           │   SSE   │ SSE progress stream      │
└─────────────────────────────┘         └──────────────────────────┘
```

## Run

```bash
pip install -r requirements.txt
streamlit run app/main.py
```

The app starts even with no server — it shows connection status and keeps the
UX usable offline. Start the pipeline server (default `http://localhost:8000`)
to generate.

## Packaging (Mac)

`packaging/mac/` holds the `.app` bundle scaffolding (`Info.plist`, icon) and
`build_dmg.sh` — run on a Mac to produce the DMG.

## CI

`.github/workflows/ci.yml` — import check + unit tests on every push/PR.
