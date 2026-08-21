# Contributing to swrly

Thanks for your interest. This is a young project — every issue and PR helps.

## Development setup

```bash
git clone https://github.com/redhotsixbull/swrly.git
cd swrly
flutter pub get
flutter analyze
flutter test
```

Run the example app:

```bash
cd example
flutter pub get
flutter run -d macos   # or ios / android / chrome
```

## Code style

- `dart format .` before committing.
- `flutter analyze` must be clean (zero info/warning/error).
- New public APIs need a dartdoc `///` comment on the class / member.
- Prefer relative imports inside `lib/src/`, package imports (`package:swrly/...`) in tests and examples.

## Tests

- Every bug fix ships with a regression test.
- New features need at least one unit test (pure logic) and, if applicable,
  one widget test.
- Async widget tests must call `client.clear()` and pump a blank widget at the
  end to avoid the "Timer still pending" assertion (see existing tests for the pattern).

## Commits

- Present-tense imperative subject: `add prefix invalidation`, not `added` or `adds`.
- Reference the issue if applicable: `add prefix invalidation (fixes #12)`.
- Keep commits small and focused. Squash before merge if the branch has noise.

## PRs

- One logical change per PR. A bug fix + an unrelated refactor = two PRs.
- Fill in the PR description: what changed, why, and how to test.
- Green CI is required.
- Breaking API changes need a `CHANGELOG.md` entry and, on merge, a minor
  version bump (pre-1.0). After 1.0 they need a major bump.

## Roadmap alignment

Before starting a large feature, please open a discussion issue or check
[ROADMAP.md](./ROADMAP.md) to see if it's already planned or explicitly
out of scope. Nothing worse than building something that gets rejected.
