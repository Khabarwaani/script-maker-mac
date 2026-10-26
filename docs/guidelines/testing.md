# Testing

Remote CI first: use GitHub Actions `xcodebuild test` on the macOS 27 runner. Local test
runs are only for diagnosing CI failures. Do not contact live providers, servers, news
services or upload destinations in unit tests. Test ViewModels and Services, never Views.

Cover agent discovery/version routing, schema validation, provider availability and
compatibility, shared-default inheritance/overrides, cancellation and session isolation.
Cover concurrent repository mutations, failed saves, corrupt reads, legacy storage,
settings migration, refinement histories, media handling and mocked upload contracts.
Fixtures belong in the test directory and must not seed or ship in the production app.

Architecture checks run before build/tests. A green suite does not authorize merging or
releasing the 2.0 revamp. Complete its acceptance checklist and obtain user approval.
