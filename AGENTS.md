# AGENTS.md — script-maker-mac

Agent rules for this repo. Written for this repo — not copied.

## Dispatch

Re-read the matching guideline each task:

| Task | File |
| :--- | :--- |
| Feature | `docs/guidelines/workflows/feature.md` |
| Bug fix | `docs/guidelines/workflows/bugfix.md` |
| Git / PR | `docs/guidelines/workflows/git.md` |
| Test or CI failure | `docs/guidelines/workflows/failure.md` |
| Unit tests | `docs/guidelines/testing.md` |
| Release | `docs/guidelines/workflows/release.md` |

## What this repo is

Native SwiftUI thin client for Script Maker. **No Python.** MVVM, async/await,
best practices throughout.

## Architecture (4 layers)

`Presentation → Domain → Platform → Infra` — dependencies point inward only.
Full spec: `docs/guidelines/architecture.md`. Layer rules: `docs/guidelines/layer-dependencies.md`.

- `Sources/ScriptMakerMac/App/` — `@main` entry + `CompositionRoot.swift` (the ONLY
  place that creates concrete types; everything else depends on protocols).
- `Sources/ScriptMakerMac/Models/` — Domain entities (`Story`, `PipelineModels`).
  Codable types, enums. No logic.
- `Sources/ScriptMakerMac/Core/` — dependency-free shared utilities
  (`DateFormatting`, `StringFormatting`, `AppLog`). Foundation only.
- `Sources/ScriptMakerMac/Services/` — Domain + Platform + Infra (see below).
- `Sources/ScriptMakerMac/ViewModels/` — `@MainActor final class : ObservableObject`.
  Owns state, calls services via protocols, exposes `@Published`. No layout code.
- `Sources/ScriptMakerMac/Views/` — dumb SwiftUI. No business logic, no direct
  service calls — everything through the view model.

Layer map inside `Services/`:

- **Domain:** `PipelineService`, `ImageService`, `StoryRepository` (protocol),
  `APIError`. Business logic. Never touches URLSession/UserDefaults directly.
- **Platform (stateful):** `LocalStoryRepository` (in-memory cache),
  `StoryDataSourceProtocol`, `UserDefaultsStoryDataSource`,
  `WebClient` (protocol), `NetworkWebClient`, `OfflineWebClient`,
  `StoryMapper`. May cache, hold session state.
- **Infra (stateless):** `InfraStore.swift` — `HTTPClient`, `KeyValueStore`,
  `FileStore`. Pure execution primitives. No app types, no state.

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
8. **Guidelines:** `docs/guidelines/` — architecture, layer-dependencies,
   workflows (feature, bugfix, git, failure, release, testing).
9. **Tokens:** fewest words in comments and terminal text.
10. **New code placement:** identify the layer first (Presentation/Domain/
    Platform/Infra/Core). If it touches a framework (URLSession, UserDefaults),
    it belongs in Infra. If it manages state/cache, Platform. Business logic,
    Domain. UI state, ViewModel. Shared helper, Core.
11. **Inject, don't create:** ViewModels/Services take `any Protocol` in
    `init`, never `ConcreteType()`. The Composition Root wires concretes.
