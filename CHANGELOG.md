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
