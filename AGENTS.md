# AGENTS.md — script-maker-mac

Agent rules for this repo. Native macOS app; conventions mirror `ai-script-maker`.

## What this repo is

Native SwiftUI thin client for Script Maker. **No Python.** MVVM, async/await,
best practices throughout.

## Architecture (MVVM)

- `Sources/ScriptMakerMac/App/` — `@main` entry only.
- `Sources/ScriptMakerMac/Models/` — Codable types, enums. No logic.
- `Sources/ScriptMakerMac/Services/` — `AppConfig` (UserDefaults, IPv6-aware URL),
  `PipelineAPI` (actor, URLSession, async/await, SSE). No UI imports.
- `Sources/ScriptMakerMac/ViewModels/` — `@MainActor final class : ObservableObject`.
  Owns state, calls services, exposes `@Published`. No UIKit/SwiftUI layout code.
- `Sources/ScriptMakerMac/Views/` — dumb SwiftUI. No business logic, no direct
  service calls — everything through the view model.

## Rules

1. **Branches & PR flow:** `main` and `develop`. Feature branches off `develop`,
   PRs target `develop`. Never push direct to `main`/`develop`.
2. **Thin client:** the UI never computes pipeline work. All generation goes
   through `PipelineAPI`. No local AI/ML imports.
3. **Fail-loud:** typed errors (`APIError`, `ConfigError`) with `LocalizedError`.
   Surfaces to the user; the UI stays usable offline.
4. **Concurrency:** async/await only — no completion handlers, no Combine for
   networking. `PipelineAPI` is an actor. ViewModels are `@MainActor`.
5. **Server URL:** top-level setting in Preferences (Cmd+, via Settings scene),
   defaults to `http://localhost:8000`. IPv6-aware normalization in `AppConfig`.
   Never hardcode another default.
6. **UX:** same use cases as the classic app. Apple HIG throughout.
7. **Testing:** CI-first (`xcodebuild` on macos). Unit tests target ViewModels
   and Services, never Views.
8. **Guidelines:** `docs/guidelines/workflows/` — feature, bugfix, git,
   failure, release, testing. Same meanings as ai-script-maker.
9. **Tokens:** fewest words in comments and terminal text.
