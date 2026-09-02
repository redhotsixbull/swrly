# Backlog Triage — 2026-09

Triage report evaluating 10 candidate features that surfaced from a
comparison against similar Flutter server-state libraries (notably
[`fquery`](https://pub.dev/packages/fquery)) and the broader
TanStack Query API surface. Six are accepted into the roadmap, two are
rejected with reasons preserved here so they don't get re-proposed
without new information.

The point of this document isn't to bench swrly against another
library — it's to catch things we may have overlooked and to record
*why* certain "obvious" additions are deliberately not adopted.

---

## Accepted — high value (v0.4 candidates)

### A1. `refetchInterval` — polling
Configurable polling interval per query. Common ask for dashboards,
status widgets, near-real-time UIs. Currently users must hand-roll a
`Timer` outside swrly and call `query.refetch()`, which sidesteps the
`isFetching` / dedupe path.

- Shape: `Query(..., refetchInterval: Duration(seconds: 30))`
- Fires only while the entry has ≥1 subscriber (no polling for dead
  entries).
- Pauses on app background; resumes with `refetchOnResume`.

### A2. `select` — data transform
Selector function applied to `state.data`; `QueryBuilder` only rebuilds
when the selected slice changes. Reduces spurious rebuilds when many
widgets share one cache entry but each reads a different field.

- Shape: `QueryBuilder.of(usersQuery, select: (u) => u.name, builder: ...)`
- Requires structural sharing (already on v0.4 as "Ergonomics") so the
  identity of unchanged slices stays stable — the two land together.

### A3. `IsFetchingBuilder` — global fetching indicator
Top-of-app pattern: "if ANY query is fetching, show a top-bar spinner."
Right now users must aggregate `isFetching` across every mounted
`QueryBuilder` themselves.

- Shape: `IsFetchingBuilder(filter: (key) => bool, builder: (isFetching) => ...)`
- Reads from `QueryClient` — no per-key subscription; watches the
  aggregate count.

### A4. Mutation `retry`
`Query` supports `retry` / `retryDelay`; `MutationBuilder` does not.
Network-flaky writes benefit from the same treatment (idempotent
mutations especially).

- Shape: `MutationBuilder(..., retry: 3, retryDelay: (n) => ...)`
- Off by default (writes are not idempotent in general) — must opt in.
- Composes with `onMutate` rollback: rollback only fires when all
  retries exhaust.

---

## Accepted — nice-to-have (Next / backlog)

### B1. `initialData` / `initialDataUpdatedAt`
Seed the cache with a value at Query definition time — useful for
hydrate-from-server-state, test fixtures, and "no loading flash on
first mount" when the value can be synthesized locally.

- Distinct from `placeholderData` (which marks the value as
  `isPlaceholderData`); `initialData` is treated as real, just not
  fresh.
- `initialDataUpdatedAt` lets the user tell swrly *when* it was fresh
  as of, so `staleTime` math is honest.

### B2. `throwOnError`
Opt-in: instead of surfacing errors through `state.error`, rethrow so
Flutter's error boundary (`ErrorWidget.builder`) or an
`ErrorBoundary`-style widget catches them. For apps with centralized
error UI.

- Off by default (breaks the render-error-in-place pattern most demos
  show).

### B3. `notifyOnChangeProps`
Rebuild the widget only when specific state fields change. Cheap opt-in
optimization for widgets that don't care about `isFetching` or
`isPlaceholderData` fluctuations.

- Shape: `QueryBuilder.of(q, notifyOn: {QueryProp.data, QueryProp.error}, ...)`
- Default: rebuild on every state change (current behavior).

### B4. Dependent queries — first-class API
Currently expressible via `QueryBuilder(enabled: otherQuery.hasData)`,
but the pattern is easy to get wrong (typo in the flag, referring to
stale data). A first-class `dependsOn` API surfaces the intent.

- Shape: `Query(..., dependsOn: [userQuery])`
- Semantics: this query's `fetch()` waits until every dep resolves with
  `hasData` and no error; propagates dep errors as this query's error.

---

## Rejected — considered but not adopted

These are the important entries — record *why*, so a future contributor
doesn't re-propose without new evidence.

### R1. `refetchOnMount: 'always' | 'never' | 'if-stale'`

**Verdict**: DO NOT ADD. Redundant with `staleTime`.

TanStack Query and several ports carry this option. The behavior space
it addresses is already fully covered by `staleTime`:

| User wants | Existing swrly API |
|---|---|
| "Always refetch on mount" | `staleTime: Duration.zero` |
| "Never refetch on mount (only manual)" | `staleTime: Duration(days: 365)` or similar large value |
| "Refetch if stale" | default — this is what `staleTime` *means* |

Adding a second axis forces users to answer "if `refetchOnMount:
'never'` conflicts with `staleTime: 30s`, which wins?" Every possible
answer is surprising to some fraction of users, and the docs cost is
disproportionate to the (zero) capability gain.

**Meta-principle**: additive convenience is welcome; **redundant axes
that overlap an existing axis are not**. If TanStack has it, that's
often API-inheritance cruft, not evidence we should follow.

### R2. Query `meta` — free-form metadata field

**Verdict**: DO NOT ADD. Solution looking for a problem.

The proposal: attach a `Map<String, dynamic>` (or similar) to each
`Query` definition, useful for logging / telemetry / DevTools.

Three problems:

1. **No consumer API today.** swrly has no logging hook, no telemetry
   emitter, no DevTools panel yet. `meta` stored but never read is
   dead weight in every cache entry.

2. **Erodes the boundary.** A free-form field teaches users that
   swrly is "throw whatever in here" instead of "narrow, opinionated
   cache." Over time this accretes app concerns into cache metadata.

3. **Preempts the right design.** When DevTools / observability lands
   (v0.5+), the right move is to design **typed** APIs for what those
   surfaces need — not to adopt a pre-existing free-form bag that then
   becomes another thing to migrate off of.

If a user needs to associate extra data with a Query for one specific
purpose, an out-of-swrly `Map<Query, ExtraData>` in their own code
works and stays out of the cache's contract.

**Reconsider when**: DevTools or a first-class observability hook is
being designed. At that point, if a typed slice of what would have
been "meta" is genuinely useful, add *that* — not the raw bag.

---

## Meta-principle for future triage

Adopt a feature only when at least one of these is true:

1. **New capability** — expresses a behavior no combination of existing
   APIs can express.
2. **Meaningful ergonomic win** — existing API technically works but
   the hand-rolled pattern is verbose enough that users routinely
   reinvent it (usually badly).
3. **Removes a footgun** — the current API lets users write broken
   code that a small addition would prevent.

Reject when:

1. **Redundant axis** — a second knob that overlaps an existing knob's
   range.
2. **Speculative extensibility** — a slot with no consumer, added
   "just in case."
3. **API-inheritance cruft** — "other libraries have it" without a
   swrly-specific reason.

---

## Also referenced (already tracked)

Not evaluated here because they're already on the roadmap or already
explicitly excluded:

- Infinite queries — v0.4 (`InfiniteQueryBuilder`)
- Request cancellation — v0.4
- Window focus / online refetch triggers — v0.4
- Persistence adapters — v0.4
- Structural sharing — Next (Ergonomics), also required by A2 above
- DevTools panel — v0.5
- Riverpod / Bloc `AsyncValue` bridges — v0.5
- `useQueries` / dynamic-parallel — explicit non-goal (too
  React-flavored; a type-safe record combinator is the preferred path)
