# Tests

Unit tests never make real calls: no network, no live LLM, no real subprocess. Mock, stub, or fake.

## Testing strategy: CI first

Testing is done in the GitHub CI pipeline (Test Suite workflow). Push the
branch and open the draft PR — CI is the verification gate. Do NOT run the local
suite routinely before pushing.

Run tests locally ONLY when they fail on the server: reproduce the CI failure
with `./runut` (or `python -m pytest tests/ -q` with `HRS_VENV=~/venvs/pw`),
fix, and confirm green locally before pushing the fix. Mark the PR ready for
review (`gh pr ready`) once server CI passes.

## Trunk assumption

Assumes develop and main are green — working condition, all tests passing.
If not, file a bug: a red trunk breaks this strategy.
