---
name: swrly-audit
description: Scan a Flutter project that uses swrly for anti-patterns — inline `Query(...)` in widgets, hardcoded string queryKeys, missing staleTime, custom objects used as keys, wrapping swrly inside another framework's cache, and other violations of doc/CONVENTIONS.md. Report findings, do not auto-fix.
---

# swrly-audit

Read-only audit. Produce a report; do not modify files.

## Prerequisites

- `swrly` in `pubspec.yaml`.

## Rules to check (each maps to a section of `doc/CONVENTIONS.md`)

### R1 — Inline `Query(...)` in a widget file (§5)

Grep:
```
grep -rn "Query<\|QueryFamily<" lib/ | grep -v "lib/queries/" | grep -v "lib/features/.*/queries/"
```

Any hit outside a queries folder is a violation.

### R2 — Hardcoded string `queryKey` (§4)

Grep for `QueryBuilder(queryKey: [...])` with string literals that
aren't part of a `Query`/`QueryFamily` definition. Prefer usage of
`QueryBuilder.of(someQuery)`.

### R3 — Missing `staleTime` (§6)

For every `Query(...)` / `QueryFamily(...)` construction, check that
`staleTime:` is present. Grep for definitions, then parse each.

### R4 — Custom object as `argKey` fallback (§7)

For every `QueryFamily<T, Arg>` where `Arg` isn't `int`, `String`,
`double`, `bool`, `num`, or a `Record` of those, check that `argKey`
is provided. If missing, flag.

### R5 — `swrly` wrapped in another framework's cache

Grep for these anti-patterns:
- `FutureProvider((.*) => .*Query.fetch()` (Riverpod wrapping swrly)
- ChangeNotifier fields typed as `List<T>` / `Future<T>` that are set
  from a swrly `fetch()` call
- Bloc state classes that mirror a swrly Query's data

Each is a double-cache. Flag.

### R6 — Broad invalidation

Grep for `invalidateQueries(const [])` or similar all-key invalidations.
That defeats the cache. Flag.

### R7 — Client state in a Query

Grep for Query definitions whose `fn` returns something purely local
(a form value, a toggle bool). Server state only. Flag.

### R8 — `Query` in a widget file

Same as R1 but specifically for widget files (`*_page.dart`,
`*_screen.dart`, `*_widget.dart`).

## Report format

Emit a Markdown report to stdout (do not write to a file unless asked):

```
# swrly-audit — <project name>

## R1 — Inline Query in widget files (2 findings)
- lib/pages/user_page.dart:42 — Query<User>(key: ['user'], ...)
- lib/pages/posts_page.dart:18 — QueryFamily<Post, int>(prefix: ['post'], ...)

## R3 — Missing staleTime (5 findings)
- lib/queries/users.dart:12 — usersQuery
- ...
```

For each finding, cite the file, line number, and a one-line hint on
what CONVENTIONS.md rule it violates.

## Do NOT

- Do NOT auto-fix. This is a report skill.
- Do NOT invent findings — every reported line must be greppable.
- Do NOT re-report the same finding under multiple rules (dedupe).

## Reference

- `doc/CONVENTIONS.md` — the ruleset.
