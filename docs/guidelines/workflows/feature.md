# Feature

Use an approved GitHub issue/spec and plan. Identify each change's layer before coding.

1. Start a separate worktree from origin/develop; never switch the primary checkout.
2. Use Observable MainActor view models and Domain protocol injection. CompositionRoot
   creates services; Views never import agent packages or call services directly.
3. Preserve user content and surface typed errors. Never invent successful results.
4. Register source/resources in the Xcode project and add meaningful service/view-model tests.
5. Push a draft PR and use remote CI. Diagnose failures under failure.md.
6. Merge only after green CI and user approval; update develop and clean merged worktrees.

For #147, implementation PRs target revamp/2.0. Keep the develop integration PR draft until
the complete revamp and acceptance testing pass. Do not create a version/preview/release
for partial work. Issue #147 stays open until every required work package is verified.
