# Feature

New use case, view, view model, or service capability. Need an approved spec
(GitHub issue) and a plan before code. Output: `feature/` branch, fail-loud
code, PR (CI runs on the server).

1. No feature commits without that spec + plan.
2. Missing data throws. No silent fallback or invented default.
3. MVVM placement:
   - Models → `Sources/ScriptMakerMac/Models/` (Codable, enums, no logic).
   - Services → `Sources/ScriptMakerMac/Services/` (actors, async/await, no UI imports).
   - ViewModels → `Sources/ScriptMakerMac/ViewModels/` (`@MainActor final class : ObservableObject`).
   - Views → `Sources/ScriptMakerMac/Views/` (dumb SwiftUI, no business logic).
4. New files go in the Xcode project (project.pbxproj) — the target must compile.
5. Server API changes come first: the thin client never computes pipeline work.

```bash
git checkout develop && git pull
git checkout -b feature/<name>
# ... work, commit ...
git push -u origin feature/<name>
gh pr create --draft --base develop --title "feat: (#<issue>) <desc>"
# verify server CI: gh pr checks
# green -> gh pr ready; red -> report (needs a Mac to reproduce)
# merge only after user approval
```
