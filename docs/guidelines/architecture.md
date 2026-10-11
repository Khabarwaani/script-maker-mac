# Architecture Principles

Enforce clean architecture: SOLID, protocol-oriented programming, dependency inversion, and layer separation.

## Layers

```
Presentation → Domain → Platform → Infra
```

- **Presentation** (`Views/`, `ViewModels/`): SwiftUI views (dumb), ViewModels (@MainActor)
- **Domain** (`Services/`: PipelineService, StoryRepository protocol, `Models/`): Business logic, entities, repository interfaces
- **Platform** (`Services/`: LocalStoryRepository, DataSources, WebClients): **Stateful** — caching, session management, repository implementations
- **Infra** (`Services/InfraStore.swift`): **Stateless** — HTTPClient, KeyValueStore, FileStore (pure execution primitives)

## SOLID

### Single Responsibility
Each class has one reason to change.

### Open/Closed
Extend via protocols, not modification. Add new `WebClient` without changing `PipelineService`.

### Liskov Substitution
Any `WebClient` (Network/Offline) works with `PipelineService`. Any `StoryRepository` works with ViewModels.

### Interface Segregation
Small focused protocols. `StoryDataSourceProtocol`: just `load()` and `save()`.

### Dependency Inversion
Depend on abstractions:
```swift
// ✅ Good
init(repository: any StoryRepository)
// ❌ Bad
init(repository: LocalStoryRepository)
```

## Protocol-Oriented Programming

1. Define protocols at layer boundaries
2. Depend on protocols, not concrete types
3. Composition Root (`App/CompositionRoot.swift`) is the ONLY place that creates concrete types

## Layer Rules

1. **Dependencies point inward**: Infra → nothing; Platform → Infra; Domain → Platform; Presentation → Domain
2. **No framework in Domain**: Never import SwiftUI, never touch UserDefaults/URLSession directly
3. **Platform is stateful**: May cache, hold sessions, coordinate
4. **Infra is stateless**: Pure functions, no caching logic, no app knowledge
5. **Testable**: Every layer mockable via protocols

## Verification

```bash
# Presentation must not import Infra
grep -r "HTTPClient\|KeyValueStore\|URLSession\|UserDefaults" Sources/ScriptMakerMac/Views/ Sources/ScriptMakerMac/ViewModels/
# Should return nothing

# Infra must not import app types
grep -r "PipelineService\|StoryRepository" Sources/ScriptMakerMac/Services/InfraStore.swift
# Should return nothing
```
