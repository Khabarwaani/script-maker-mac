# Script Maker for Mac

Native macOS thin client for Script Maker. **No Python** — pure Swift/SwiftUI,
MVVM, async/await throughout.

Requires **macOS 27+ and Xcode 27+**. Studio and Library use the
pipeline server configured in Preferences (Cmd+,). The **LocalAgent** tab runs
KhabarwaaniAgent through an installed terminal AI provider.

- **Server URL** defaults to `http://localhost:8000`.
- **Server URL** is a top-level setting (IPv6-aware) — point it at a remote server anytime.
- **Long generations** stream progress via Server-Sent Events; the UI never blocks.
- **Failures** offer the same four options as the classic app: retry stage, retry fresh, skip, dismiss.

---

## LocalAgent

Keep the local KhabarwaaniAgent checkout beside this repository. AgentAtom and
TerminalAgentSession resolve from GitHub release ranges; KhabarwaaniAgent stays
a local path dependency.

Validated with KhabarwaaniAgent 1.1.0, including ThreeSceneStoryCreator 2.1.0
and its progressive Inquire → Clarify → Payoff instructions. Agent versions come
from discovery metadata; the app does not pin or relabel them.

The Agent dropdown and its Version dropdown share one row. Both come from the
package's `KhabarwaaniAgent.agents` discovery descriptors and executable hooks.
The app has no agent enum or per-agent form switch. Register a new
`DiscoverableAgentSpec` in the package, rebuild, and its form appears automatically.

Input controls come from JSON Schema: strings, numbers, integers, booleans,
enums, optional and nullable values, nested objects, and arrays. Defaults are
preserved. Invalid edits remain visible and prevent Run. **Input JSON** shows
the same payload validated and sent to the package executor. Drafts are retained
separately per agent/version while the app is open. Changing agents selects the
latest executable stable version.

Historical versions listed only as discovery metadata remain unavailable until
the package supplies their executor. Selecting an older version never executes
the current spec under that version number.

Unavailable providers are disabled. Research agents require a terminal provider;
Apple Intelligence runs compatible agents on-device. Runtime settings remain
separate per provider. Codex, Claude, Antigravity and Grok use installed CLI
accounts. Each Run uses a temporary workspace with cleanup and cooperative
cancellation. Raw JSON and typed decoding errors remain available for inspection.

Script refinement is an ordinary catalog agent. The dedicated Script Refine tab,
its server integration, settings, and Library fine-tuning flow have been removed.
There is no automatic import of agent results into Studio or Library. Humans
review content quality.

The CLI launcher supplies EOF on stdin, adds executable search paths, captures
stdout for failure details, and closes strict object schemas. It translates
Grok's schema option and omits permission-bypass flags from provider defaults.

This integration currently uses the package discovery-hook branch in CI, pending
its dependency PR. Production release checkouts continue to use package main.
CI needs the existing read-only `KHABARWAANI_AGENT_READ_KEY` for that private
checkout. The xcode-27 runner supplies macOS/Xcode 27.

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
