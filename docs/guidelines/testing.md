# Tests

Unit tests never make real calls: no network, no live server. Mock, stub, or fake.

## Testing strategy: Remote CI first

Testing is performed in GitHub Actions CI (`xcodebuild` on macOS). Push the branch and open
the draft PR — remote CI is the verification gate. Do not run local test suites during routine
development; run tests locally only when diagnosing and reproducing a failure reported by CI.

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
