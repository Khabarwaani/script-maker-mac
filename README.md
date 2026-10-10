# Script Maker for Mac

Native macOS thin client for Script Maker. **No Python** — pure Swift/SwiftUI,
MVVM, async/await throughout.

Same use cases as the classic app. Every task goes over HTTP to the pipeline
server configured in Preferences (Cmd+,); nothing is computed locally.

- **Works offline**: server defaults to `http://localhost:8501` — no internet needed.
- **Server URL** is a top-level setting (IPv6-aware) — point it at a remote server anytime.
- **Long generations** stream progress via Server-Sent Events; the UI never blocks.
- **Failures** offer the same four options as the classic app: retry stage, retry fresh, skip, dismiss.

---

## Architecture

Clean 4-layer architecture (inspired by `abhi266raj/Camera`):

```
Presentation → Domain → Platform → Infra
```

### Layer Descriptions

**1. Presentation** (`Views/`, `ViewModels/`)
- SwiftUI views (dumb — no business logic, no service calls)
- ViewModels (`@MainActor`, `ObservableObject`) — UI state, calls Domain services
- Depends on: Domain

**2. Domain** (`Services/`: PipelineService, StoryRepository protocol, Models)
- Business logic, entities, repository interfaces
- `PipelineService`: orchestrates pipeline via WebClient
- `StoryRepository` protocol: defines persistence contract
- Depends on: Platform (via protocols only)

**3. Platform** (`Services/`: LocalStoryRepository, StoryDataSourceProtocol, WebClients)
- **Stateful**: caching, session management, repository coordination
- Repository implementations, DataSource protocols, DTOs, mappers
- `LocalStoryRepository`: implements Domain's protocol using DataSources (can cache)
- `NetworkWebClient` / `OfflineWebClient`: implement `WebClient` protocol (hold baseURL, session config)
- Depends on: Infra (via protocols/wrappers)

**4. Infra** (`Services/`: InfraStore.swift)
- **Stateless**: pure execution primitives, no caching, no business logic
- Dumb framework wrappers — no app types, no state
- `HTTPClient`: URLSession wrapper — just executes requests
- `KeyValueStore`: UserDefaults wrapper — just reads/writes
- `FileStore`: FileManager wrapper — just file I/O
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
5. **Platform is stateful, Infra is stateless**: Platform may cache, hold session state, coordinate. Infra just executes — no caching logic, no state.
6. **Protocol-oriented**: Depend on protocols, not concrete types. Every layer boundary is a protocol.
7. **SOLID**:
   - Single Responsibility: Each class has one reason to change
   - Open/Closed: Extend via protocols, not modification
   - Liskov: Subtypes must be substitutable (e.g., any `WebClient` works)
   - Interface Segregation: Small focused protocols (`StoryDataSourceProtocol`)
   - Dependency Inversion: High-level modules depend on abstractions

---

## Open in Xcode

Open `ScriptMakerMac.xcworkspace` (or `ScriptMakerMac.xcodeproj`) at the repo root.

## Build the DMG (on a Mac)

```bash
packaging/mac/build_dmg.sh 1.0
```

## CI

`.github/workflows/ci.yml` — `xcodebuild` Debug build on every push/PR (public repo: free).
