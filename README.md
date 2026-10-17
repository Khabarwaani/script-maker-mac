# Script Maker for Mac

Native macOS thin client for Script Maker. **No Python** — pure Swift/SwiftUI,
MVVM, async/await throughout.

Requires **macOS 27+ and Xcode 27+**. Studio, Library, and Script Refine use the
pipeline server configured in Preferences (Cmd+,). The **LocalAgent** tab runs
KhabarwaaniAgent through an installed terminal AI provider.

- **Server URL** defaults to `http://localhost:8000`.
- **Server URL** is a top-level setting (IPv6-aware) — point it at a remote server anytime.
- **Long generations** stream progress via Server-Sent Events; the UI never blocks.
- **Failures** offer the same four options as the classic app: retry stage, retry fresh, skip, dismiss.

---

## LocalAgent

Keep the unpublished `KhabarwaaniAgent` checkout beside this repository:

```text
Khabarwaani/
  ScriptMakerMac/
  KhabarwaaniAgent/
```

Open the Xcode workspace and let Swift Package Manager resolve **AgentAtom** and
**TerminalAgentSession** from GitHub releases. Release ranges allow new major
and minor releases; the resolver selects the latest version satisfying the whole
graph. No exact release or local checkout is pinned by the app. Use Xcode's
**File → Packages → Update to Latest Package Versions** to refresh an existing
resolution. The local KhabarwaaniAgent package uses your working-tree sources.

In LocalAgent, choose **3-Scene Story Creator** (news, optional joke, output count)
or **Shekhar Joke Generator** (output count, news count, jokes per category).
Choose Codex, Claude, Antigravity, or Grok and sign in to that CLI beforehand,
or choose **Apple Intelligence (on-device)** to use AgentAtom's native Mac
session. Missing CLIs and unavailable Apple Intelligence models are grayed out
and cannot be selected. **Refresh providers** rechecks availability; installed
CLIs still need valid provider authentication. Executables are found on PATH,
`/opt/homebrew/bin`, and `/usr/local/bin`.

Expand **Session settings** for the package's runtime process mode, memory
policy, and execution metadata. The on-device provider offers temperature
instead of terminal process/memory settings. CLI model overrides are in the
main form. Settings are kept separately per provider while the app is open.
Each Run creates a new session; provider capabilities determine process support.
Codex and Claude normalize persistent stdin/stdout to one-shot execution.
Metadata appears only when the provider returns and retains it.
The on-device session runs the supplied-news 3-scene tool; Shekhar's fresh-news
research tool requires a terminal provider and is disabled for Apple Intelligence.

Run displays readable results and preserves the exact final response under
**Raw output**, including undecodable responses. Output text is selectable for
copying. Each run uses a temporary working directory and does not write into
your repositories. Cancel requests cooperative CLI cancellation and keeps Run
disabled until cleanup finishes. Provider access may require internet and uses
your existing CLI account. Results remain in memory while switching tabs;
automatic import into Studio/Library is not included.

The CLI launcher supplies EOF on stdin for GUI launches, adds executable
search paths to the child environment, and captures stdout for failure details.
The package adapter closes derived object schemas for strict structured output,
including nullable optional fields. It translates Grok's schema option to the
installed CLI's `--json-schema` interface and does not forward permission-bypass
flags inserted by provider defaults.

CI and release workflows check out `KhabarwaaniAgent`'s `develop` branch beside
the app. Workflows try their GitHub token; if cross-repository access is denied,
configure `KHABARWAANI_AGENT_READ_TOKEN` with read access to the private package.
The `xcode-27` runner provides macOS 27/Xcode 27. Tests fake sessions and never
invoke a live provider.

## Architecture

Clean 4-layer architecture (inspired by `abhi266raj/Camera`):

```
Presentation → Domain → Platform → Infra
```

### Layer Descriptions

**1. Presentation** (`Views/`, `ViewModels/`)
- SwiftUI views (dumb — no business logic, no service calls)
- ViewModels (`@Observable`, `@MainActor`) — UI state, calls Domain services
- Depends on: Domain

### Observation Framework

ViewModels use the modern Observation framework (`@Observable`), not the legacy `ObservableObject`/`@Published`:

```swift
@Observable
@MainActor
final class LibraryViewModel {
    var stories: [Story] = []   // plain var — no @Published needed
    ...
}
```

Views hold models with `@State` (owner) and `@Bindable` (needs `$` bindings):

```swift
struct ContentView: View {
    @State private var libraryViewModel: LibraryViewModel  // created once, stays in memory
    ...
}
struct StoryListView: View {
    @Bindable var viewModel: LibraryViewModel  // $viewModel.selectedStoryID bindings
    ...
}
```

Rules: ViewModels are created once (in `ContentView`) and passed down — never recreated on tab switch. Each section is its own `View` struct for stable identity.

**2. Domain** (`Services/`: PipelineService, StoryRepository protocol, Models)
- Business logic, entities, repository interfaces
- `PipelineService`: orchestrates pipeline via WebClient
- `StoryRepository` protocol: defines persistence contract
- Depends on: Platform (via protocols only)

**3. Platform** (`Services/`: LocalStoryRepository, StoryDataSourceProtocol, WebClients)
- Repository implementations, DataSource protocols, DTOs, mappers
- `LocalStoryRepository`: implements Domain's protocol using DataSources
- `NetworkWebClient` / `OfflineWebClient`: implement `WebClient` protocol
- Depends on: Infra (via protocols/wrappers)

**4. Infra** (`Services/`: InfraStore.swift)
- Dumb framework wrappers — no business logic, no app types
- `HTTPClient`: URLSession wrapper
- `KeyValueStore`: UserDefaults wrapper
- `FileStore`: FileManager wrapper
- Depends on: nothing (dependency-free)

### Layered Interaction Model

- **View** displays ViewModel state and forwards user actions
- **ViewModel** prepares data for UI and delegates to Domain services
- **Domain** performs business logic using Platform abstractions
- **Platform** implements persistence/network using Infra wrappers
- **Infra** provides raw framework access with no app knowledge

### Responsibility Matrix

| Layer        | Responsibilities                              | Depends On     |
|--------------|-----------------------------------------------|----------------|
| Presentation | UI rendering, state management                | Domain         |
| Domain       | Business logic, entities, repository contracts| Platform       |
| Platform     | Repo impls, DataSources, WebClients, DTOs      | Infra          |
| Infra        | URLSession, UserDefaults, FileManager wrappers| None           |

### Rules

1. **Dependencies point inward**: Infra knows nothing about Platform; Platform knows nothing about Domain.
2. **Protocols at boundaries**: Domain defines `StoryRepository`; Platform defines `StoryDataSourceProtocol`; Infra provides concrete wrappers.
3. **No framework in Domain**: Domain never imports SwiftUI or touches UserDefaults/URLSession directly.
4. **Testable**: Every layer can be mocked via protocols.

---

## Open in Xcode

Open `ScriptMakerMac.xcworkspace` (or `ScriptMakerMac.xcodeproj`) at the repo root.

## Build the DMG (on a Mac)

```bash
packaging/mac/build_dmg.sh 1.0
```

## CI

`.github/workflows/ci.yml` — `xcodebuild` Debug build on every push/PR (public repo: free).
