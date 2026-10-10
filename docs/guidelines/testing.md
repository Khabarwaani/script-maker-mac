# Tests

Unit tests never make real calls: no network, no live server. Mock, stub, or fake.

## Testing strategy: CI first

Testing is done in GitHub CI (`xcodebuild` on macos). Push the branch and open
the draft PR — CI is the verification gate. Do NOT attempt local builds: this
VM is Linux and cannot run Xcode.

A red CI run cannot be reproduced here. Report the failing step verbatim and
stop — do not guess at fixes without the Mac build log.

## What to test

- ViewModels and Services, never Views.
- `AppConfig.normalize`: valid URLs, IPv6 (bare/bracketed/with port),
  and every fail-loud rejection.
- `PipelineAPI`: mocked `URLSession` — session/stage/select/job payloads,
  error mapping, SSE parsing.
- No test hits the real server.

## Trunk assumption

Assumes develop and main are green. If not, file a bug: a red trunk breaks
this strategy.
