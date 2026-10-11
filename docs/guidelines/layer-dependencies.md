# Layer Dependency Rules

What each layer can depend on, what it cannot, and how to verify.

## The Rule

```
Presentation → Domain → Platform → Infra
```

Dependencies point **inward** only. No layer may depend on an outer layer.

## Allowed Dependencies

| From         | Can depend on             | Cannot depend on              |
|--------------|---------------------------|-------------------------------|
| Presentation | Domain (protocols)        | Platform, Infra               |
| Domain       | Platform (protocols only) | Presentation, Infra directly  |
| Platform     | Infra (wrappers)          | Presentation, Domain impl     |
| Infra        | Nothing (stdlib only)     | Any app layer                 |

## Verification

```bash
# Presentation must not import Infra
grep -r "HTTPClient\|KeyValueStore\|FileStore\|URLSession\|UserDefaults" \
  Sources/ScriptMakerMac/Views/ Sources/ScriptMakerMac/ViewModels/
# Should return nothing

# Domain must not touch frameworks directly
grep -rn "URLSession.shared\|UserDefaults.standard" \
  Sources/ScriptMakerMac/Services/PipelineService.swift \
  Sources/ScriptMakerMac/Services/StoryRepository.swift
# Should return nothing (uses WebClient/DataSource protocols instead)

# Infra must not import app types
grep -rn "PipelineService\|StoryRepository\|WebClient" \
  Sources/ScriptMakerMac/Services/InfraStore.swift
# Should return nothing
```

## Common Violations

### ViewModel creating a concrete repository
```swift
// ❌ Bad: depends on concrete Platform type
final class MyViewModel {
    private let repo = LocalStoryRepository()
}
```
```swift
// ✅ Good: depends on Domain protocol, injected
final class MyViewModel {
    private let repo: any StoryRepository
    init(repository: any StoryRepository) {
        self.repo = repository
    }
}
```

### Service using URLSession directly
```swift
// ❌ Bad: Domain touching Infra framework
struct MyService {
    func fetch() async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
```
```swift
// ✅ Good: Domain uses Platform abstraction
struct MyService {
    private let webClient: any WebClient
    func fetch() async throws -> Data {
        try await webClient.fetchData(from: url)
    }
}
```

### View doing networking
```swift
// ❌ Bad: Presentation touching Infra
struct Thumbnail: View {
    func load() async {
        let (data, _) = try await URLSession.shared.data(from: url)
    }
}
```
```swift
// ✅ Good: View → ViewModel → Service → WebClient
struct Thumbnail: View {
    @StateObject var viewModel: ThumbnailViewModel
    var body: some View { /* binds to viewModel.image */ }
}
```

## Operating Rules

1. Before adding an import, check which layer you are in.
2. If you need something from an outer layer, define a protocol in your layer instead.
3. The Composition Root (`App/CompositionRoot.swift`) is the ONLY place that creates concrete types.
4. When in doubt, draw the dependency arrow — it must point inward.
