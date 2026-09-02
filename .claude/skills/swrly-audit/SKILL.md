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

```
grep -rnE "\bQueryBuilder<" lib/ | grep -v "QueryBuilder\.of"
```

The regex intentionally does NOT try to match the closing `>` of the
generic — `QueryBuilder<List<Post>>(` has a nested `>` that a simple
`[^>]+>` pattern would stop at. Match just the opening `QueryBuilder<`
and let `grep -v` peel off the `QueryBuilder.of` case.

Any raw `QueryBuilder<T>(...)` (not `QueryBuilder.of(...)`) that
constructs its own `queryKey` inline is a candidate — the user hasn't
wrapped their (key, fn) pair in a `Query`/`QueryFamily` definition, so
key typos become silent cache misses. Prefer `QueryBuilder.of(someQuery)`.

### R3 — Missing `staleTime` (§6)

`grep` alone can't catch this — `Query(...)` / `QueryFamily(...)`
constructions span multiple lines. Find every queries file recursively
first, then extract each definition and check for `staleTime:`:

```
# 1) Locate every queries file, not just top-level or nested-only.
find lib -type f -name '*.dart' -path '*/queries/*' > /tmp/swrly-queries.txt

# 2) For each, extract Query<...> AND QueryFamily<...> definition ranges
#    and flag those without `staleTime:`.
while IFS= read -r f; do
  awk -v file="$f" '
    /Query</ || /QueryFamily</ { block=""; capture=1 }
    capture { block = block $0 "\n" }
    /\);/ && capture {
      if (block !~ /staleTime/) print file ":" NR " missing staleTime"
      capture = 0
    }
  ' "$f"
done < /tmp/swrly-queries.txt
```

Feature-organized projects (`lib/features/*/queries/*.dart`) are picked
up because `find -path '*/queries/*'` matches at any depth.

For a Dart-native approach: `dart run` a small script that parses each
queries file's AST and reports each constructor call whose named-arg
list has no `staleTime`. AST is more robust than the shell version if
users have unusual formatting.

### R4 — Custom object as `argKey` fallback (§7)

For every `QueryFamily<T, Arg>` where `Arg` isn't `int`, `String`,
`double`, `bool`, `num`, or a `Record` of those, check that `argKey`
is provided. If missing, flag.

### R5 — `swrly` wrapped in another framework's cache

Three shapes to look for:

```
# a) Riverpod wrapping swrly.
grep -rnE "(FutureProvider|StreamProvider|AsyncNotifier).*Query\.fetch" lib/

# b) ChangeNotifier / Cubit holding a fetched List/Model.
#    A single `grep -A 30 | grep` intersection MISSES the common shape
#    where the field is declared on one line and assigned from
#    Query.fetch() on a different line. Iterate class blocks instead.
for f in $(grep -rlE "class .*(ChangeNotifier|Cubit)" lib/); do
  awk '
    /class .*(ChangeNotifier|Cubit)/ { in_class=1; block=""; header=$0 }
    in_class { block = block $0 "\n" }
    in_class && /^}/ {
      if (block ~ /(List<|Future<|AsyncValue<)/ && block ~ /[Qq]uery.*\.fetch/) {
        print FILENAME ": " header
      }
      in_class = 0
    }
  ' "$f"
done

# c) Bloc state class named like a Query's data (heuristic — often a
#    sign of a data Bloc that should be a plain Query instead).
grep -rnE "class .*(Loaded|Success|Loading|Error)" lib/
```

Each match is a **candidate** double-cache. Read the file to confirm
the Query result is being stored redundantly before flagging.

### R6 — Broad invalidation

Grep for `invalidateQueries(const [])` or similar all-key invalidations.
That defeats the cache. Flag.

### R7 — Client state in a Query

Grep for Query definitions whose `fn` returns something purely local
(a form value, a toggle bool). Server state only. Flag.

### R8 — (removed)

Was a duplicate of R1 with a narrower file-name filter. R1 already
catches every inline `Query`/`QueryFamily` outside `lib/queries/`
regardless of file name; the separate rule was noise.

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
