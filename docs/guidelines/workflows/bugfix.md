# Bug fix

Crash, CI fail, UI drift, broken API contract. Minimal diff. Keep issue refs (`#N`).

1. Fix root cause. No silent `catch` that swallows errors.
2. No unrelated edits.
3. Fail-loud: typed errors (`APIError`, `ConfigError`) surface to the user;
   the UI stays usable offline — never a fatal crash for a server hiccup.
4. Reopening: if the bug carries the `code completed` label, remove it on reopen
   and add `reopened` — the work wasn't actually complete.
5. Flow:

```bash
git checkout develop && git pull
git checkout -b fix/<issue>-<name>
# ... fix, commit ...
git push -u origin fix/<issue>-<name>
gh pr create --draft --base develop --title "fix: (#<issue>) <desc>"
# verify server CI: gh pr checks
# green -> gh pr ready; red -> report (needs a Mac to reproduce)
# merge only after user approval
```
