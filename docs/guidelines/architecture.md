# Architecture

Presentation renders state and calls Domain protocols. Platform implements those
protocols using Infra primitives. Domain is independent of Platform, Infra and UI/provider
frameworks. Core contains shared Foundation-only utilities.

- **App:** CompositionRoot wires concrete services and owns stable view-model instances.
- **Presentation:** Observable MainActor view models own UI state. Views display that state
  and forward actions. Settings and agent-selection dependencies use focused protocols.
- **Domain:** entities, typed requests/errors, repository/settings interfaces, pipeline
  execution validation and story mapping. Foundation only; no framework access.
- **Platform:** stateful settings, provider adapters, discovery clients, actor repositories
  and serialization/migration. Framework execution is delegated to Infra wrappers.
- **Infra:** HTTP, key-value, filesystem, clipboard, sharing and credential primitives.

Generation uses LocalAgentRunning and package executors. There is no pipeline-server,
sample-mode or server model catalog. News/media/uploads retain direct HTTP.

Retained agent resources are owned by session ID and effective settings. Acquire a lease
before execution, release it on every outcome, and dispose resources on replacement/close.
Repositories serialize complete mutations and update cache only after successful writes.
