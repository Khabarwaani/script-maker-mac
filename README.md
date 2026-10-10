# Script Maker for Mac

Native macOS thin client for Script Maker. **No Python** — pure Swift/SwiftUI,
MVVM, async/await throughout.

Same use cases as the classic app. Every task goes over HTTP to the pipeline
server configured in Preferences (Cmd+,); nothing is computed locally.

- **Works offline**: server defaults to `http://localhost:8000` — no internet needed.
- **Server URL** is a top-level setting (IPv6-aware) — point it at a remote server anytime.
- **Architecture**: MVVM — `Sources/ScriptMakerMac/{App,Models,Services,ViewModels,Views}`.
- **Long generations** stream progress via Server-Sent Events; the UI never blocks.
- **Failures** offer the same four options as the classic app: retry stage, retry fresh, skip, dismiss.

## Open in Xcode

Open `ScriptMakerMac.xcworkspace` (or `ScriptMakerMac.xcodeproj`) at the repo root.

## Build the DMG (on a Mac)

```bash
packaging/mac/build_dmg.sh 1.0
```

## CI

`.github/workflows/ci.yml` — `xcodebuild` Debug build on every push/PR (public repo: free).
