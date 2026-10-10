# AGENTS.md — script-maker-mac

Agent rules for this repo. Mirrors `ai-script-maker` conventions.

## What this repo is

Thin-client Mac UI for Script Maker. Streamlit frontend, talks HTTP to the
pipeline server. Same UX as the classic app — only the data layer changed.

## Rules

1. **Branches & PR flow:** `main` and `develop`. Feature branches off `develop`,
   PRs target `develop`. Never push direct to `main`/`develop`.
2. **Thin client:** the UI never imports the pipeline. All generation goes
   through `app/api_client.py`. No `agents.*` imports anywhere in this repo.
3. **Fail-loud:** no silent fallbacks. `ServerUnreachable` / `ServerError`
   surface to the user; the UI stays usable offline.
4. **UX:** same components, theming and Apple HIG compliance as the classic
   app. Reusable views live in `app/views/`.
5. **Server URL:** top-level setting, defaults to `http://localhost:8000`
   (`app/config.py`). Never hardcode another default.
6. **Testing:** CI-first on the server. `python -m pytest tests/ -q`.
7. **Guidelines:** `docs/guidelines/workflows/` — feature, bugfix, git,
   failure, release, testing. Same meanings as ai-script-maker.
8. **Tokens:** fewest words in comments and terminal text.

## Layout

- `app/` — Streamlit thin client (`main.py`, `api_client.py`, `config.py`)
- `assets/` — app icon (AppIcon.iconset, also wired into Xcode)
- `packaging/mac/` — Xcode project + DMG build script (run on a Mac)
- `tests/` — unit tests
