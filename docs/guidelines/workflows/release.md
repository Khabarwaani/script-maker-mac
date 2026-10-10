# Release

Version bump, spec, audit, publish.

1. Approved `docs/REQUIREMENTS_vX.Y.md` (or `vX.Y_REQUIREMENTS.md`) and `vX.Y_IMPLEMENTATION_PLAN.md` before feature commits.
2. Version bumps: use `ci-cd/cd/bump_version.sh <X.Y.Z>` (cuts branch, merges `main` in `--no-ff`, bumps `core/version.py`, opens PR).
3. Never squash version/release PRs: merge with `./merge_pr <num> --merge` (true merge) to keep history intact.
   Squash creates divergent history → phantom GitHub conflicts on the next release PR (#526, #528).
   Use `ci-cd/cd/release.sh <X.Y.Z>` — it hard-codes `--merge` so squash is impossible.
4. After `main` is tagged, start the next spec. Mark prior requirements done or not; ask user to abandon or defer incomplete items.

## Versioning

- `main` carries the last released version (tagged). `develop` keeps that version in its header while the next release's work accumulates — many PRs may merge to develop with no bump; unreleased develop builds may all show the same version.
- Bump exactly once per release, after the release content is final: `ci-cd/cd/bump_version.sh <X.Y.Z>`. A premature mid-cycle bump forces a second bump for the same release.

Steps: draft spec + plan → wait for approval → implement → bump via `ci-cd/cd/bump_version.sh` → true-merge to develop → build the release PR body with `./ci-cd/cd/release_closing_keywords.sh` (`Closes #N` per fixed issue — fix PRs target develop and never auto-close on their own; without this, shipped issues stay open) → true-merge develop to `main` → tag `vX.Y.Z` → CI (`release_package.yml`) builds the DMG and attaches it to the GitHub Release automatically → verify the release actually has the DMG asset (a glob miss once published an empty release) → audit with user → seed next spec.

DMG notes: the build itself needs macOS (`cd/build_macos_app.sh --release`; cannot run in the Linux VM). Manual fallback for the upload: `ci-cd/cd/publish_release.sh --version X.Y.Z` (idempotent).
