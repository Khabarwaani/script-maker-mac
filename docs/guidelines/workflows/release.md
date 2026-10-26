# Release

Version bump, notes, DMG, publish.

1. Release only after ALL open PRs are merged and CI is green on develop.
2. Version: bump `CFBundleShortVersionString` / `CFBundleVersion` in
   `Sources/ScriptMakerMac/Resources/Info.plist`, exactly once per release.
3. Merge `develop` into `main` (PR, user-approved), then tag `vX.Y.Z` on the
   merge commit.
4. Releases go out ONLY by tag push (`v*`) — never created manually in the
   GitHub UI. The tag triggers the DMG build.
5. Verify the release actually has the DMG asset attached before announcing.
6. After tagging, start the next cycle. Mark prior release notes done.

## Versioning

- `main` carries the last released version (tagged). `develop` accumulates the
  next release's work — many PRs may merge with no version bump.
- A version increase is not a release. The DMG on the GitHub Release is.

For #147, finish the complete revamp and its tests before any version bump, preview or
release. The CI workflow supports an explicitly dispatched acceptance artifact only
after its build/tests pass; it preserves the current version and never publishes a tag.
