# Script Maker for Mac

Native macOS thin client for Script Maker. **No Python** — pure Swift/SwiftUI,
MVVM, async/await throughout.

Requires **macOS 27+ and Xcode 27+**. Studio uses the pipeline server configured in Preferences (Cmd+,).
Library saves and enriches stories locally with direct HTTP requests. The **LocalAgent** tab runs
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

Validated with KhabarwaaniAgent 1.4.1, including ThreeSceneStoryCreator 2.2.0
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

## Library

Use **Add** with just a title/headline. Script, generation metadata and media are
optional. The Mac searches news feeds (Bing, then Google News), reads publisher
Open Graph / Twitter images and checks image availability. Hashtags are derived
from the title locally. No AI, Python or ScriptMakerServer is used. Internet is
needed for search and uploads. Search failures keep the saved story and show the
cause; refresh related content to retry. Editing a title saves a new copy and
refreshes its related content while preserving the original and imported images.

**Share → Upload to Telegram** sends the title/hashtags, optional local video,
then source links. It reads the same `~/Documents/telegrambot/bot_token.txt` and
`~/.cache/telegram_bot_chat_id.json` as ScriptMaker. Enter a chat ID or tap Start
in the bot to establish your destination. Group sending is opt-in and uses
`~/Documents/telegrambot/group_ids.txt` plus discovered groups. The sheet also
accepts a temporary token/chat override. Upload errors report partial delivery;
retrying may resend messages that already arrived.

**Share → Upload to Google Drive / Sheets** ports ScriptMaker’s Kops reel upload.
Attach a local MP4, MOV or WebM video first; only this upload endpoint requires
video. Authentication uses `GOOGLE_ACCESS_TOKEN`, then `~/.clasprc.json` (run
`npx clasp login`), then an optional temporary access token. The default Apps
Script deployment matches ScriptMaker and can be overridden in the upload sheet.
The returned Drive preview, sheet row and timestamp are saved with the story.
The existing Drive text export remains available separately.

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
packaging/mac/build_dmg.sh 1.1.0
```

## CI

`.github/workflows/ci.yml` — `xcodebuild` Debug build on every push/PR (public repo: free).

Studio news discovery runs locally in Swift using the public personal packages
[NewsSearch](https://github.com/abhi266raj/NewsSearch) and
[TrendingHashtag](https://github.com/abhi266raj/TrendingHashtag). Local categories
remain fixed; only selected headlines or hashtag details refresh. Internet is required.
Bundled sample mode remains available. Script generation still uses the configured
pipeline server. Both packages offer source and XCFramework products at the same
version; this app consumes the framework products.

Settings contains app-wide News Discovery and Trending Hashtags options, initialized
to the frameworks' defaults. Configure search/trend windows, cache durations,
providers, region, language, and result limits there. Hashtag selection shows feed
details; **Load full title and description** looks up additional topic context.

In Library, open a story with a screenplay and choose **Refine with Script Chat**.
Choose an available local provider, enter a refinement instruction, and review the
updated draft. Each turn keeps the original script and carries the latest draft
and consolidated instructions forward. **Save as new script** creates a separate
Library entry with version history and a link to the source story. Closing or
cancelling does not save or change the original. This uses KhabarwaaniAgent 1.3.0;
installed CLI providers require their existing sign-in, or use available Apple
Intelligence. Generated video and upload receipts are cleared on the refined copy.

Script Chat shows the read-only original script beside the current script and
editable consolidated instructions. Original instructions are kept internally as
conversation context. Refine applies consolidated-instruction edits; discard them
to restore the last successful instructions before saving. Refinement history instructions are
editable: **Apply history edits** regenerates from the first changed turn through
later turns. A failed or cancelled replay preserves the last successful draft.
Apply or discard history edits before refining again or saving a new entry.
