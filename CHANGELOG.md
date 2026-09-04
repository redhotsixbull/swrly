## 0.4.0-dev.1

First slice of the v0.4 line — four additive ergonomic knobs, no breaking
changes:

- **`Query.initialData` / `initialDataUpdatedAt`** — seed a cache entry with a
  real value at first observation, distinct from `placeholderData` which
  never persists. Function-form (`T Function()?`) sidesteps the "was `null`
  omitted or genuinely null?" ambiguity. Pair with `initialDataUpdatedAt`
  when hydrating from a source that was fresh some time ago, so the
  freshness clock stays honest. `QueryFamily` variant takes
  `T Function(A arg)?` so each member can synthesize its own seed.
  Per [`BACKLOG_TRIAGE.md B1`](doc/BACKLOG_TRIAGE.md).
- **`Query.refetchInterval`** — per-query polling. Ticks only while the entry
  has ≥1 subscriber, pauses when the last subscriber leaves and re-arms
  on re-subscribe. Each tick behaves like `refetch()` — bypasses
  `staleTime`, dedupes against an in-flight fetch. Per
  [`BACKLOG_TRIAGE.md A1`](doc/BACKLOG_TRIAGE.md).
- **`MutationBuilder.retry` / `retryDelay`** — matches the retry knob `Query`
  already has. Off by default (writes aren't idempotent in general). An
  `onMutate` rollback runs only after **all** retries exhaust, so the
  optimistic UI survives transient failures a retry recovers from. Per
  [`BACKLOG_TRIAGE.md A4`](doc/BACKLOG_TRIAGE.md).
- **`QueryBuilder.notifyOn` + `QueryProp`** — cheap opt-in rebuild filter. Pass
  `{QueryProp.data, QueryProp.error}` and the widget stops rebuilding on
  `isFetching` flicker or `updatedAt` bumps it doesn't render. Default
  (`null`) matches previous behaviour. Per
  [`BACKLOG_TRIAGE.md B3`](doc/BACKLOG_TRIAGE.md).

`swrly_hooks` bumps in lockstep to `0.4.0-dev.1` (no source changes required —
the new options flow through as `Query` fields, which the hooks already read).

## 0.3.1

Ecosystem release — **no changes to `lib/`**, the public API is byte-identical
with `0.3.0`. This release exists to broadcast the surrounding scaffolding
that landed since:

- **`swrly_hooks` companion package** ([pub.dev](https://pub.dev/packages/swrly_hooks))
  — `useSwrlyQuery` / `useSwrlyMutation` for `HookWidget`-based screens.
  Split into its own package so hook non-users don't pay for
  `flutter_hooks` as a transitive dep; version-locked to swrly's own
  `major.minor` (matching pattern to `flutter_riverpod` / `hooks_riverpod`).
- **`example/lib/patterns/`** — 5 runnable side-by-side demos of swrly
  combined with `setState` / Provider / Riverpod / Bloc / hooks, all
  driving the same posts screen so the differences are visible at a
  glance. See the README's "Using with your state management" section.
- **`.claude/skills/`** — 9 Claude Code skills (`swrly-init`,
  `swrly-refactor-{futurebuilder,stateful,provider,riverpod,bloc,hooks,spaghetti}`,
  `swrly-audit`) that scaffold and refactor swrly usage in downstream
  Flutter projects. Each skill was end-to-end verified against a real
  Flutter project (fresh scaffold, plus flutter_weather and the
  rrousselGit/riverpod pub example for the more complex cases).
- **`AGENTS.md`** at repo root — a living rulebook AI coding assistants
  (Claude Code, Cursor, Aider, Copilot, Windsurf, ...) can follow when
  writing any server-state code in a swrly project, not just refactors.
  Point the assistant at the raw GitHub URL and it defaults to swrly
  conventions for new features and fetches deeper `.claude/skills/*`
  procedures on demand.
- **`doc/CONVENTIONS.md`** — the single-source rulebook every skill
  cites. Split out of the design plan so both people and AI can consult
  one file for the "swrly-shaped code" contract.

All existing 70 tests unchanged and passing (widget tests in
`swrly_hooks` unchanged too). `swrly_hooks` bumps in lockstep to
`0.3.1-dev.1`.

## 0.3.0

Stable release of the 0.3.0 line (the `0.3.0-dev.*` notes below are the full
history). Headline additions since `0.2.x`:

- **`Query<T>` / `QueryFamily<T, A>` — query definition objects.** Declare a
  query's key, fetch function and options **once**, then consume that same
  definition imperatively (`postsQuery.fetch()` / `refetch()`), declaratively
  (`QueryBuilder.of(postsQuery, builder: ...)`) or for cache control (`data` /
  `state` / `stream` / `setData` / `invalidate` / `remove`). Retyping the
  `(key, fn)` pair at every call site made a mistyped key a silent cache miss
  rather than a compile error; a definition is the single spelling of the key.
  The cache still lives in `QueryClient` — a `Query` is a stateless value
  object, and two definitions with the same key address the same entry.
  See SPEC §10.
- **`QueryFamily`** for parameterised queries — keys are always
  `[...prefix, ...argKey(arg)]`, so `invalidateAll()` / `removeAll()` are
  correct by construction.
- **`Query.invalidate()` / `Query.remove()` are exact**, not prefix-scoped;
  `invalidateQueries(prefix)` / `removeQueries(prefix)` keep prefix semantics.
- **`QueryClient.removeQueriesWhere(test)`** — predicate form of
  `removeQueries`, mirroring `invalidateQueriesWhere`.
- **Docs that can't rot** — the README carries no version literals, and
  `docs_freshness_test.dart` / `readme_snippets_test.dart` fail the suite on a
  version literal, a CHANGELOG that has drifted from `pubspec.yaml`, an
  undocumented public type, or a code sample that no longer compiles.

**70 tests**; `lib/src` stays at 100% line coverage (330/330). Backward
compatible with `0.2.x` — purely additive.

## 0.3.0-dev.2

Documentation hygiene — no API changes.

- **The README no longer carries version numbers.** Every release meant editing
  a status line, two "New in X" lists, an Install pin, an inline `(0.2.0)`
  marker and a "Shipped in" recap — and it rotted twice (0.2.0 shipped while the
  README still called it a prerelease and pinned `^0.1.0`). Now `pubspec.yaml`
  is the version, `CHANGELOG.md` is the history, the pub.dev badge renders the
  current number, and the README only describes what the library does. The two
  "New in X" lists are replaced by one version-free **What you get**; Install is
  `flutter pub add swrly`.
- **New: `test/docs_freshness_test.dart`.** Three guards that fail the suite
  rather than relying on remembering: the README must contain no version
  literal, `CHANGELOG.md`'s newest entry must match `pubspec.yaml`, and every
  public type must have an entry in `doc/API.md`. Together with
  `readme_snippets_test.dart` (which compile-checks the samples), the docs now
  break the build when they drift instead of going stale quietly.
- The public-type guard immediately found one gap: `QueryKeyHash` had no entry
  in `doc/API.md`. Documented, along with `queryKeyStartsWith` — both are useful
  inside an `invalidateQueriesWhere` / `removeQueriesWhere` predicate.

## 0.3.0-dev.1

First 0.3.0 feature, on the `dev` prerelease track for real-world verification.

- **New: `Query<T>` / `QueryFamily<T, A>` — query definition objects.** Declare a
  query's key, fetch function and options **once**, then consume the same
  definition three ways: imperatively (`postsQuery.fetch()` / `refetch()`),
  declaratively (`QueryBuilder.of(postsQuery, builder: ...)`), or for cache
  control (`data` / `state` / `stream` / `setData` / `invalidate` / `remove` /
  `copyWith`). Previously the `(key, fn)` pair had to be retyped at every call
  site, where a mistyped key is a silent cache miss rather than a compile error.
  A `Query` is a stateless value object — the cache still lives in
  `QueryClient`, and two definitions with the same key address the same entry.
  See SPEC §10.
- **`QueryFamily`** covers parameterised queries. Keys are always
  `[...prefix, ...argKey(arg)]` (default `[arg]`), so `invalidateAll()` /
  `removeAll()` are correct by construction; supply `argKey` when the argument
  is a record or custom object so the key is built from primitives instead of
  `toString()`.
- **`Query.invalidate()` / `Query.remove()` are exact**, not prefix-scoped — a
  definition names one entry, so invalidating `['posts']` leaves
  `['posts', 'page', 2]` alone. `invalidateQueries(prefix)` /
  `removeQueries(prefix)` keep their prefix semantics.
- **New: `QueryBuilder.of(query, builder: ...)`** — build a widget straight from
  a definition. Because a definition's `fn` is a stable field rather than an
  inline closure, the `queryFn` re-captured for invalidation refetches is
  identical across builds.
- **New: `QueryClient.removeQueriesWhere(test)`** — predicate form of
  `removeQueries`, mirroring `invalidateQueriesWhere`.
- **Docs:** README "Define a query once" section, SPEC §10, API reference for
  both types; the SPEC's out-of-scope list no longer claims 0.2.0 features are
  missing, and ROADMAP's duplicate `v0.2` section is folded into `v0.4`.
- **Tests:** 15 new tests for the definition objects, plus a new
  `test/readme_snippets_test.dart` that compile-checks every Dart snippet in
  the README and `doc/API.md` against the real API, so a doc example can't
  drift from the code without the suite going red. 67 tests total; `lib/src`
  stays at 100% line coverage (330/330).

Backward compatible with `0.2.x` — purely additive.

## 0.2.1

- **Fix: `observe()` / `stateOf()` no longer disarm garbage collection.** Both go
  through the internal entry lookup, which cancels a pending GC timer so an
  entry can't be disposed out from under a caller — but neither re-armed it, so
  observing (or synchronously reading) a key with no subscribers left the entry
  resident forever, and `stateOf` on an *unknown* key leaked the idle entry it
  created. Both now re-arm GC, matching `fetchQuery` / `setQueryData`. Entries
  with a live subscriber (a mounted `QueryBuilder`) are unaffected. Found while
  documenting the non-widget path below.

- **README: "Using swrly without widgets".** `QueryClient` is a complete API on
  its own; the README now documents the imperative path (`fetchQuery`) and the
  observe path (`observe` / `stateOf`) alongside `QueryBuilder`, with a table of
  the three ways to read a query and patterns for prefetch-before-navigate,
  synchronous peeks and non-widget subscriptions.
- **Documented that `observe()` does not register a subscriber**, so it does not
  hold an entry against `cacheTime` GC (README + `doc/API.md`).
- README status/install corrected for the released `0.2.0` (they still described
  `0.2.0` as a prerelease and pinned `^0.1.0`).
- **Example:** don't notify instrumentation `ValueNotifier`s during build.
- **Tests:** 50 (3 new, covering the GC re-arm); `lib/src` stays at 100% line coverage.

## 0.2.0

Stable release of the 0.2.0 line (the `0.2.0-dev.*` notes below are the full
history). Headline additions since `0.1.x`:

- **Retry + backoff** — `retry` / `retryDelay` on `QueryBuilder` / `fetchQuery`,
  exponential default (1s→30s).
- **Optimistic updates with automatic rollback** — `MutationBuilder.onMutate`
  applies an optimistic write and returns a rollback closure run on error.
- **`keepPreviousData` / `placeholderData`** — no loading flash on key changes
  (search / pagination); new `QueryState.isPlaceholderData`.
- **Example:** a new **Stress test** screen — an in-app performance harness with
  a live FPS / build / raster / jank readout, a cache-ops micro-benchmark, and
  hundreds of live `QueryBuilder`s under continuous invalidation.
- **Docs:** the README now has a measured **Performance** section.

Backward compatible with `0.1.x`.

## 0.2.0-dev.4

- **Example:** rebuilt as a verification harness for all 0.2.0 features —
  pagination with `keepPreviousData` (dimmed previous page while loading), a
  "Fail next" retry demo, and a "make next create fail" toggle that shows the
  optimistic insert being rolled back automatically.
- **Tests:** 100% line coverage on `lib/src` (added `refetch()`,
  `refetchOnResume`, custom-key `toString` fallback, idle getters, singleton).
- **Docs:** added `doc/VERIFICATION.md` (status, remaining TODOs, how to verify
  the prerelease). README updated for the 0.2.0-dev feature set.

## 0.2.0-dev.3

- **New: `keepPreviousData` / `placeholderData`.** `QueryBuilder.keepPreviousData`
  keeps rendering the previous key's data (flagged `state.isPlaceholderData`)
  while a new key loads, instead of flashing to a spinner — ideal for search /
  pagination. `QueryBuilder.placeholderData` shows a static stand-in until the
  first real value arrives. Neither is cached or affects freshness. New
  `QueryState.isPlaceholderData` flag. See SPEC §9.

## 0.2.0-dev.2

- **New: optimistic updates with automatic rollback.** `MutationBuilder.onMutate`
  runs before `mutationFn`, applies your optimistic write, and returns a rollback
  closure; swrly runs it automatically on error (before `onError`) and keeps the
  optimistic value on success. Backward compatible — existing
  `onSuccess`/`onError`/`onSettled` signatures are unchanged. See SPEC §9.

## 0.2.0-dev.1

First 0.2.0 feature, on the `dev` prerelease track for real-world verification.

- **New: retry + backoff.** A `queryFn` that throws is retried up to `retry`
  times with a `retryDelay(attempt)` backoff. Configure per query
  (`QueryBuilder.retry` / `retryDelay`, `fetchQuery(retry:, retryDelay:)`) or
  globally (`QueryClient(defaultRetry:, defaultRetryDelay:)`). Default is `0`
  retries (unchanged 0.1.x behaviour); `defaultRetryDelayFn` provides an
  exponential 1s→30s backoff. While retrying the query stays `isFetching` and
  only surfaces an `error` after retries are exhausted; retries respect the
  generation guard (a supersede/dispose stops them). See SPEC §8.1.

## 0.1.1-dev.1

Prerelease of the 0.1.1 correctness patch, published for verification before the
stable `0.1.1` release. Everything below plus the review fix noted here.

- **Fix (review):** `QueryBuilder` only re-captures the refetcher (`primeRefetcher`)
  on a same-key rebuild **when `enabled` is true**. Previously a disabled query
  that rebuilt could get a refetcher installed, so a later `invalidateQueries`
  would fetch a query the caller set `enabled: false` — violating SPEC §9. Added
  a regression test plus tests for `onError`/`onSettled` on unmount, `hasData`
  retention across errors, and `copyWith` field clearing (31 tests total).

## 0.1.1

Correctness patch — behaviour fixes found in review, all backward compatible.

- **Fix:** `QueryState.hasData` is now based on a stored "has a successful value"
  flag instead of `data != null`. A query that legitimately resolves to `null`
  now reports `isSuccess && hasData` at the widget layer, matching the cache's
  own freshness contract (SPEC §2/§5.1).
- **Fix:** `QueryState.copyWith` can now **clear** `data`/`error`/`stackTrace`
  (via a sentinel). Entering a fetch and a successful refetch clear a stale
  error/stackTrace, so an old failure no longer leaks into a later
  loading/success state.
- **Fix:** `MutationBuilder` now runs `onSuccess`/`onError`/`onSettled`
  **regardless of `mounted`** — a widget that disposes mid-flight no longer
  silently skips a cache invalidation done in `onSuccess`. Only `setState` is
  guarded.
- **Fix:** `QueryBuilder` re-captures the current `queryFn`/`staleTime` on a
  same-key rebuild (new `QueryClient.primeRefetcher`), so a later
  `invalidateQueries` refetch uses the current closure rather than a stale one.
  It still does **not** refetch on a plain `queryFn` identity change.
- **New:** `QueryClient.invalidateQueriesWhere((key) => bool)` — predicate form
  of `invalidateQueries` for sets a prefix can't express.
- **Docs:** documented the last-writer-wins semantics for an entry's captured
  `queryFn` when subscribers share a key (SPEC §6). Added 6 tests.

## 0.1.0

- **Example:** rebuilt around a real **dio** client hitting a public API, with a
  live request counter + event log so the cache is *observable* — cache hits
  show as "0 requests", keyed detail queries (`['post', id]`) demonstrate
  per-key caching, and mutations show optimistic `setQueryData`. Runs on web.
- **Docs:** README overhauled — "why server state", how-it-works flow, and
  comparison tables (vs `FutureBuilder`, vs Riverpod/Bloc, vs a dio cache
  interceptor). `docs/` renamed to `doc/` (pub convention); added pubspec topics.
- Bundles all the `0.0.2` cache-correctness fixes below.

## 0.0.2

- **Fix:** `invalidateQueries(refetch: true)` now actually refetches active
  subscribers (the last `queryFn` is captured per entry) instead of only
  marking data stale.
- **Fix:** stale responses can no longer overwrite fresher data — each fetch
  carries a generation token and only the newest may write back.
- **Fix:** a successful `null` value is treated as fresh; nullable-data queries
  no longer refetch on every call.
- **Fix:** freshness uses a monotonic clock, immune to wall-clock jumps.
- **Fix:** garbage collection can no longer dispose an entry that is being
  reused imperatively; idle imperatively-created entries are now collected too.
- **Fix:** `QueryBuilder` kicks off the fetch when `enabled` flips false → true.
- Docs: added `docs/SPEC.md`; expanded test coverage (dedup, race, GC,
  nullable, invalidate-refetch, widget lifecycle).

## 0.0.1

- Initial scaffold: `QueryClient`, `QueryBuilder`, `MutationBuilder`, prefix invalidation, refetch-on-resume.
