# Bug fix

Crash, UT fail, CSS/UI drift, pipeline regression. Minimal diff. Keep issue refs (`#138`, `#217`).

1. Fix root cause. No silent try/catch wrappers.
2. No unrelated edits.
3. Warnings: `st.warning()`, never fatal `st.error()` (#217).
4. Reopening: if the bug carries the `code completed` tag, remove it on reopen — the work wasn't actually complete, and the tag hides the bug from triage.
5. Flow: `./create_branch fix/<issue>-<name>` (auto-links issue in GitHub), commit, `./open_pr` (auto-draft). Verify server CI (`gh pr checks`). Green → `gh pr ready`. Red → reproduce locally with `./runut`, fix, push, then `gh pr ready`.

| Action | Command |
| :--- | :--- |
| Branch | `./create_branch fix/<issue>-<name>` |
| PR | `./open_pr -t "fix: (#<issue>) <desc>"` |
| CI status | `gh pr checks` |
| Ready | `gh pr ready` |
| CI fail triage | `./runut` |
| Merge | `./merge_pr <num>` (only after user approval) |

