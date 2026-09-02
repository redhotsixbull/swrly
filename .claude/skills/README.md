# swrly Claude Code Skills

Skills that scaffold, refactor, and audit `swrly` usage in Flutter
projects.

## Available skills

| Skill | What it does |
|---|---|
| [`swrly-init`](swrly-init/) | Install swrly into a Flutter project, scaffold `lib/queries/`, detect state-mgmt for tailored setup. Does NOT refactor existing code. |
| [`swrly-refactor-futurebuilder`](swrly-refactor-futurebuilder/) | Convert `FutureBuilder` → `QueryBuilder`. The safest migration. |
| [`swrly-refactor-stateful`](swrly-refactor-stateful/) | Kill the `_isLoading` / `_error` / `_data` trio in a `StatefulWidget`. |
| [`swrly-refactor-provider`](swrly-refactor-provider/) | Strip server state out of `ChangeNotifier`s in a Provider project. |
| [`swrly-refactor-riverpod`](swrly-refactor-riverpod/) | Migrate `FutureProvider`s that hand-roll `staleTime` to swrly `Query`. |
| [`swrly-refactor-bloc`](swrly-refactor-bloc/) | Replace data Blocs with swrly; keep state-machine Blocs, swap their repository cache. |
| [`swrly-refactor-hooks`](swrly-refactor-hooks/) | Install canonical `useSwrlyQuery` snippet + refactor `HookWidget` fetches. |
| [`swrly-refactor-spaghetti`](swrly-refactor-spaghetti/) | Legacy no-state-mgmt cleanup — map first, convert one screen at a time. |
| [`swrly-audit`](swrly-audit/) | Read-only anti-pattern report. |

## Common ground

Every skill:

- Reads [`doc/CONVENTIONS.md`](../../doc/CONVENTIONS.md) for its rules.
- Points at [`example/lib/patterns/`](../../example/lib/patterns/) as
  the canonical target shape.
- Never batch-converts — always one file / screen / provider per diff.
- Never adds features swrly doesn't ship (persistence, cancellation,
  infinite queries) — refuses with a roadmap pointer.

## Plan

The design behind these skills lives in
[`doc/CLAUDE_SKILLS_PLAN.md`](../../doc/CLAUDE_SKILLS_PLAN.md).
