---
name: swrly-refactor-spaghetti
description: For legacy Flutter projects with no state-management library and fetches scattered across widgets, produce a scoped migration plan — map fetch sites, prioritize, then convert one screen at a time via swrly-refactor-stateful. Use when the user asks to clean up a legacy fetch-anywhere codebase, or make swrly adoption safe in a messy project.
---

# swrly-refactor-spaghetti

Legacy Flutter code with fetches inside widgets, `bool _isLoading` fields
scattered, page transitions retriggering requests. The wrong response is
a giant refactor PR. The right response is a **map first, then convert
screen by screen**.

## Prerequisites

- `swrly` in `pubspec.yaml` (`swrly-init` if not).
- `lib/queries/` exists.
- User has agreed this will take multiple sessions.

## Step 1 — Draw the map. Do NOT write code yet.

Grep the whole project:

```
grep -rn "http.get\|dio.get\|api\." lib/
grep -rn "_isLoading\|_loading" lib/
grep -rn "initState" lib/
grep -rn "FutureBuilder" lib/
```

Assemble a table:

| File | Screen/Widget | Fetch(es) | Also uses |
|---|---|---|---|
| `lib/pages/home.dart` | `HomePage` | `api.getPosts()` in initState | `_isLoading`, retry button |
| ... | ... | ... | ... |

Present this to the user. Do not proceed to code until the user picks a
starting point.

## Step 2 — Prioritize with the user

Suggest starting with:

- **Highest reuse** (a fetch called from many screens — biggest win from
  caching).
- **Simplest widget** (a leaf StatefulWidget with `_isLoading` — fits
  `swrly-refactor-stateful` cleanly).
- **Most obviously stale** (a fetch that runs on every push and users
  notice the spinner).

Explicitly reject:

- "Convert everything at once."
- "Convert this deeply intertwined controller + widget hybrid first."

## Step 3 — Convert one screen. Confirm. Then the next.

For the chosen screen, invoke `swrly-refactor-stateful` (or
`swrly-refactor-futurebuilder` if that's the shape). Each conversion is:

1. Extract the fetch to a `Query` in `lib/queries/`.
2. Rewrite the widget.
3. Show the diff. Wait for approval.
4. Suggest a manual test path (open screen, close, reopen within
   `staleTime` → observe no new request).
5. Suggest a single commit (not squashed with other conversions).

## Step 4 — Keep the map alive

After each conversion, update the map (which screens have moved, which
haven't). This is how the user knows they're making progress without
holding it all in their head.

## Anti-patterns to actively refuse

- **Bulk find-and-replace.** Refuse even if the user asks.
- **"Let me just introduce a state-management library while I'm here."**
  That's a separate project; scope creep will kill the migration.
- **Rewriting the API layer.** swrly caches whatever `queryFn` returns.
  Don't reshape the API in the middle of a cache migration.
- **Fixing lint issues in the same PR.** Separate concern.

## Reference

- `doc/CONVENTIONS.md §1` — the "no destructive rewrite" rule.
- `example/lib/patterns/plain/` — where each screen ends up.
