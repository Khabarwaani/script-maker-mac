# Git / PR

Any code change. Start from `origin/develop`. End: branch pushed, PR open, merge only after user approval.

1. No push or merge to `main` or `develop`. PR only.
2. No force-push — emergency only, with explicit user permission each time.
3. Branch names: `feature/<name>`, `fix/<issue>-<name>`, `refactor/<name>`, `chore/<name>`.
4. Plain git + `gh` (this repo has no wrapper scripts):

```bash
git checkout develop && git pull
git checkout -b feature/<name>
# ... work, commit ...
git push -u origin feature/<name>
gh pr create --draft --base develop --title "feat: (#<issue>) <desc>"
```

5. CI runs xcodebuild on the macOS runner. Run local tests only to diagnose CI failures.
6. Test fail: [`failure.md`](./failure.md).
7. Ready for review vs failure triage:
   - Server CI passes (green) → `gh pr ready [<pr>]`.
   - Server CI fails (red) → report the failure; reproducing needs a Mac.
8. Merge only after user says yes: `gh pr merge <num> --squash`.
9. Issues: `gh issue create --type Bug|Feature|Task` (types, never labels).
10. Review threads: fix, push, then reply on the PR. Never resolve only in the GitHub UI.
11. Keep the primary checkout on current `develop`; use a separate worktree for
    implementation. After approved CI passes, merge the PR into `develop`, update
    the primary checkout, and remove the merged branch locally/remotely and its
    worktree. Do not discard unmerged work during cleanup.
12. Local launch verification uses integrated `develop` and Xcode's default
    DerivedData location; no custom `-derivedDataPath` or repo-local build output.

For #147, implementation PRs target revamp/2.0; its integration PR stays draft until the
whole revamp is tested and approved. No partial develop merge or new version/preview.
