# Tests by responsibility

- ViewModels: selection, validation, state transitions, errors, draft preservation,
  navigation callbacks and successful-save behavior.
- Domain services: exact agent/version routing, request preparation and output mapping.
- Platform: provider/session adaptation, independent owners, cancellation, memory modes,
  atomic repository mutations, settings migration and storage-failure recovery.
- Infra adapters: mock network responses and isolated filesystem/key-value stores.

Do not test SwiftUI Views. Do not invoke paid/live agent sessions or real uploads from
automated tests. Legacy story fixtures verify compatibility, not production demo behavior.
