# Testing Each Layer

How to test every architecture layer. Unit tests target ViewModels and
Services, never Views (per AGENTS.md rule 7).

## What to Test per Layer

| Layer        | Test                                     | Example                              |
|--------------|------------------------------------------|--------------------------------------|
| Presentation | ViewModel state transitions              | `LibraryViewModel.refresh()` updates `stories` |
| Domain       | Service logic, protocol contracts        | `ImageService` returns nil offline    |
| Platform     | Repository behavior, caching, mapping    | `LocalStoryRepository` newest-first, cache invalidation |
| Infra        | Thin wrappers (mostly trivial)            | `KeyValueStore` round-trip           |
| Core         | Pure functions                           | `StringFormatting.displayKey`, `StoryMapper` round-trip |

## Patterns

### Mock via protocols
```swift
// Test doubles implement the Domain protocol
struct FakeStoryRepository: StoryRepository {
    var stored: [Story] = []
    func save(_ story: Story) async { stored.append(story) }
    func all() async -> [Story] { stored }
    func remove(id: String) async { stored.removeAll { $0.id == id } }
}

func testViewModelUsesRepository() async {
    let fake = FakeStoryRepository()
    let vm = LibraryViewModel(config: testConfig, repository: fake)
    await vm.refresh()
    XCTAssertEqual(vm.stories.count, fake.stored.count)
}
```

### Test Platform caching
```swift
func testCacheInvalidatedOnMutation() async {
    let repo = LocalStoryRepository()
    await repo.save(Story(id: "c1", title: "Cached"))
    XCTAssertTrue(await repo.all().contains { $0.id == "c1" })
    await repo.remove(id: "c1")
    XCTAssertFalse(await repo.all().contains { $0.id == "c1" })
}
```

### Test mappers with round-trips
```swift
func testStoryMapperRoundTrip() {
    let original = Story(id: "rt", title: "T", videoURL: "http://x/v.mp4")
    let restored = StoryMapper.from(StoryMapper.toDict(original))
    XCTAssertEqual(restored.id, original.id)
    XCTAssertEqual(restored.videoURL, original.videoURL)
}
```

### Test legacy migration
When changing persistence formats, add a migration test:
```swift
func testLegacyDictionaryMigration() {
    // Write old-format JSON, verify new code reads it
}
```

## Rules

1. **Never test Views** — test the ViewModel's `@Published` state instead.
2. **Mock at layer boundaries** — fake the protocol, not the concrete type.
3. **Test behavior, not implementation** — assert on observable outcomes
   (stories list contents), not internal cache state.
4. **Isolate UserDefaults in tests** — save/restore surrounding state, or inject
   a `KeyValueStore` backed by a test suite.
5. **CI is build-only today** — `xcodebuild build` in `.github/workflows/ci.yml`.
   Tests run locally via Xcode. (A `xcodebuild test` CI job is future work.)

## Current Coverage

`Tests/ScriptMakerMacTests/`:
- `AppConfigTests.swift` — URL normalization, IPv6
- `SampleAPITests.swift` — offline fixtures
- `SampleDataTests.swift` — bundled JSON
- `RepositoryTests.swift` — repository CRUD, ordering, cache invalidation,
  legacy migration, mapper round-trips, ImageService, offline WebClient
