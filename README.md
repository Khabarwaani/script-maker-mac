# Script Maker for Mac

Native SwiftUI macOS app for local KhabarwaaniAgent workflows. Requires macOS 27+
and Xcode 27+. Generation runs through installed Codex, Claude, Antigravity or Grok
CLIs, or compatible Apple Intelligence agents. Terminal providers use their existing
sign-in. Internet is needed for news discovery, research and uploads.

## Workspaces

- **Researcher:** browse NewsSearch categories/headlines and TrendingHashtag topics;
  run NewsResearcher with a terminal provider supporting web research.
- **Library:** save stories, scripts, media and refinement history; enrich news,
  images and hashtags directly on the Mac. Share/export or explicitly upload to
  Telegram and Google Drive/Sheets. Failed enrichment keeps the saved story.
- **LocalAgent:** package-discovered agents/versions with schema-generated inputs,
  advanced per-provider session settings and inspectable raw output.
- **Pipeline:** Preset or Configurable agent workflows with continuous or step-wise
  execution, editable outputs, explicit transitions and Library export.
- **Script Detail:** independently saved scenes and iterative visual detailing.
- **Agents & Instructions:** inspect package agent metadata, instructions and schemas.

Settings (Cmd+,) defines a shared default provider and optional model override.
Each workspace can use that default or override it. An empty model uses the
provider's default; the app does not invent model or reasoning capabilities.
Unavailable/incompatible selections block Run with a reason; they are never silently
replaced. Existing configured pipeline steps retain their provider selections.

Agent versions are package metadata. A historical version without its own executor
cannot run the current executor under an old version number. Retained sessions are
isolated by owner and effective execution settings; requests for one owner serialize.
Cancelling or closing one session does not clear other workspaces' memory.

## Storage and upgrades

The Library and Script Detail use separate persisted collections and actor-backed
repositories with atomic JSON files. Existing UserDefaults collections are read until\nthe first successful file save; compatibility keys stay updated for rollback. Failed reads\npreserve original bytes and surface an error. Failed writes
preserve the last successful cache and editable drafts. No sample stories are inserted.
Existing stories, media paths, upload receipts, generation metadata and chat histories
remain readable, including legacy story dictionaries.

The revamp migrates recognized legacy provider/model settings once, then retires the
server/sample settings. Unknown legacy providers initialize the Codex default. News,
trending, appearance and upload credentials remain independent of generation routing.
Server generation, demo mode and server-only closing-clip merging have been removed.

Media imports copy user-selected files into Application Support. Upload credentials
are stored in Keychain. Separate candidate bundle identifiers use independent
preferences, media namespaces and Keychain services. Production retains its existing
storage paths and Keychain service for compatibility.

## Development

Open `ScriptMakerMac.xcworkspace` or `ScriptMakerMac.xcodeproj`. The local package
reference expects a sibling `KhabarwaaniAgent` checkout. CI checks out tag 2.0.2 and
resolves AgentAtom, TerminalAgentSession, NewsSearch and TrendingHashtag dependencies.

Presentation depends on Domain protocols; Platform implements them using Infra
primitives. Domain imports Foundation only. `App/CompositionRoot.swift` creates and
wires services and stable workspace view models. Views display state and forward actions.
Stateful settings/persistence belong in Platform; raw framework execution belongs in Infra.

Run architecture checks with `bash scripts/check-architecture.sh`. GitHub Actions is
the automated test gate; unit tests use mocks and never invoke live agents or uploads.
Local tests are for diagnosing CI failures. Local builds use default Xcode DerivedData.

## 2.0 integration gate

[Issue #147](https://github.com/Khabarwaani/script-maker-mac/issues/147) tracks the full
revamp. Implementation stays on `revamp/2.0` and its PR branches. `develop` and `main`
receive no partial revamp integrations. Finish the whole implementation, pass automated
and acceptance testing, and obtain user approval before integrating. No new version,
preview or release is created before the whole revamp is tested. The checked-in version
remains unchanged until release preparation.
