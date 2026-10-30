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
- `Sources/ScriptMakerMac/Domain/` — `Entities/` (`Story`, agent/pipeline models),
  `Services/` (business logic + protocols: `PipelineExecutionService`,
  `StoryRepository`, `LocalAgentRunning`). Never touches URLSession/UserDefaults directly.
- `Sources/ScriptMakerMac/Core/` — dependency-free shared utilities
  (`DateFormatting`, `StringFormatting`, `AppLog`). Foundation only.
- `Sources/ScriptMakerMac/Platform/` — `Repositories/`, `DataSources/`, `WebClients/`,
  `Mappers/`. Stateful implementations (caching, sessions).
- `Sources/ScriptMakerMac/Infra/` — `InfraStore.swift` (`HTTPClient`, `KeyValueStore`,
  `FileStore`). Stateless execution primitives; AppConfig is in Platform.
- `Sources/ScriptMakerMac/Presentation/ViewModels/` — `@Observable @MainActor final class`.
  Owns state, calls services via protocols. Plain `var` (no `@Published`).
  Created once by CompositionRoot, retained by App/ContentView state, passed as `@Bindable`.
  Never recreated. No layout code.
- `Sources/ScriptMakerMac/Presentation/Views/` — dumb SwiftUI. No business logic, no direct
  service calls — everything through the view model. Each section its own struct.

## Rules

1. **Branches & PR flow:** `main` and `develop`. Feature branches off `develop`,
   PRs target `develop`. Complete integrations by merging the approved, green PR
   into `develop`; leaving code only on a feature branch is not completion.
   Never push direct to `main`/`develop`. Delete merged feature branches locally
   and remotely. Preserve unmerged work until integrated or explicitly discarded.
   Keep the primary checkout on current `develop`. Make implementation changes
   in a separate Git worktree; do not switch the user's primary checkout.
   Remove the worktree after merging and verifying the integration.
2. **Agent execution:** use injected local agent services and package executors.
   Views never import agent packages. News/media/uploads use direct HTTP adapters.
3. **Fail-loud:** typed errors (`APIError`, `ConfigError`) with `LocalizedError`.
   Surfaces to the user; the UI stays usable offline.
4. **Concurrency:** async/await only — no completion handlers, no Combine for
   networking. Repositories and retained session coordination are actors. ViewModels are `@MainActor`.
5. **Settings:** shared typed agent default with workspace overrides. No server/sample
   mode. Unknown or incompatible provider selections block Run without substitution.
6. **UX:** same use cases as the classic app. Apple HIG throughout.
7. **Testing:** Remote CI-first (`xcodebuild` on GitHub Actions). Rely on CI
   for test verification; run local tests only upon CI failure. Unit tests target
   ViewModels and Services, never Views.
8. **Guidelines:** `docs/guidelines/` — architecture, layer-dependencies,
   workflows (feature, bugfix, git, failure, release, testing).
9. **Tokens:** fewest words in comments and terminal text.
10. **New code placement:** identify the layer first (Presentation/Domain/
    Platform/Infra/Core). If it touches a framework (URLSession, UserDefaults),
    it belongs in Infra. If it manages state/cache, Platform. Business logic,
    Domain. UI state, ViewModel. Shared helper, Core.
11. **Inject, don't create:** ViewModels/Services take `any Protocol` in
    `init`, never `ConcreteType()`. The Composition Root wires concretes.
12. **Local builds and launch:** use the integrated `develop` checkout and
    Xcode's default DerivedData location. Build with `xcodebuild -project
    ScriptMakerMac.xcodeproj -scheme ScriptMakerMac -configuration Debug
    -destination 'platform=macOS' build`, then launch with Xcode's Product > Run.
    Do not create repo-local `build/` output or custom DerivedData directories.
    When verifying a launch, check the running executable's path and that app's
    `Info.plist` version. Multiple DerivedData copies share the same app name and
    bundle ID, so selecting an app by name alone can reopen a stale build.

## 2.0 revamp exception (#147)

Implementation PRs target revamp/2.0. Keep develop/main free of partial revamp work.
Finish every work package and testing before creating a new version, preview or release.
The develop integration remains draft until full acceptance and explicit user approval.
