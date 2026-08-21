# 0.2.0 verification & status

Tracking doc for the `0.2.0` prerelease line (`dev` branch). `main` stays the
stable release line; `dev` publishes `0.2.0-dev.N` prereleases for real-world
verification before the stable `0.2.0` promotion.

## Done in 0.2.0-dev

| Feature | Where | Tests |
|---|---|---|
| Retry + backoff | `retry`/`retryDelay` on `QueryBuilder`/`fetchQuery`; `defaultRetry`/`defaultRetryDelay` on `QueryClient` | ✅ unit + E2E |
| Optimistic updates + automatic rollback | `MutationBuilder.onMutate` returns a rollback closure | ✅ unit + E2E |
| `keepPreviousData` / `placeholderData` | `QueryBuilder`; `QueryState.isPlaceholderData` | ✅ unit + E2E |
| (0.1.1) predicate invalidation, hasData/copyWith/rollback-safety fixes | see CHANGELOG | ✅ |

**Quality gates (must stay green):** `flutter analyze` clean · `flutter test`
all pass · **100% line coverage** on `lib/src` · `example/` builds for web ·
Playwright E2E (16 assertions) green.

## Still ahead (TODO)

Roughly in priority order — details in [`ROADMAP.md`](ROADMAP.md):

- [ ] **Request cancellation** — abort in-flight fetch when the last subscriber
      leaves; thread an abort token into `queryFn` (signature change, so 0.2.0
      or later). Robustness gap.
- [ ] **Infinite / paginated queries** — `InfiniteQueryBuilder` with
      `getNextPageParam`.
- [ ] **Non-widget `QueryObserver`** — imperative subscribe for Bloc/services.
- [ ] **Window/online refetch triggers** — beyond the existing app-resume.
- [ ] **Persistence adapter interface** — hive / shared_preferences / drift.
- [ ] **Typed error surfaces** — network-vs-parse distinction.
- [ ] **Ecosystem** — DevTools panel, Riverpod/Bloc `AsyncValue` bridges.
- ⊘ **`useQueries`** — intentionally skipped (too React-flavored). If parallel is
      needed, prefer a type-safe record combinator (`QueryGroup2/3Builder`).

## How to verify the prerelease

### 1. The example app (dogfooding harness)

`example/` (dio, real API) has controls to exercise every 0.2.0 feature:

- **Retry** — tap **Fail next** → the next 2 posts fetches fail then recover
  (watch the log: `✗ … ✗ … ✓`, and `dio requests` ticks per attempt).
- **keepPreviousData** — use the **page** pager → the current list stays
  (dimmed, "loading page…") while the next page loads, instead of a spinner.
- **Optimistic rollback** — flip **Make next create fail** then **Create** →
  the post appears instantly (`onMutate`), the create fails, and it is
  automatically rolled back (`↩ rollback` in the log).

```bash
cd example && flutter run -d chrome   # or any device
```

### 2. Automated browser E2E (Playwright)

The cache semantics + all three 0.2.0 features are asserted end-to-end against
the built web example by counting real API calls and driving the Flutter
semantics tree. See the session's `scratchpad/pw/cache-test.js` (16 assertions).

### 3. Pull the prerelease into your own app

```yaml
dependencies:
  swrly: 0.2.0-dev.3   # pin exactly; prereleases aren't matched by ^ ranges
```

## Promotion checklist (dev → stable 0.2.0)

- [ ] Prerelease exercised in a real app for the intended use cases
- [ ] No correctness/UX issues found
- [ ] Bump `pubspec.yaml` to `0.2.0`, finalize `CHANGELOG.md` (fold the
      `-dev.N` notes into a single `0.2.0` entry)
- [ ] Merge PR (`dev` → `main`)
- [ ] `flutter pub publish` the stable `0.2.0` (done by a human)
