---
description: List recent harness cycles from .harness/history/INDEX.json with optional filters.
---

Read `.harness/history/INDEX.json` (created by `/harness-iterate`'s archive step — see harness-iterate.md §8). Each entry is a compact summary; this command prints them one per line, most recent first.

## Arguments (parse from `$ARGUMENTS`)

| Flag | Meaning |
|---|---|
| (none) | Most recent 10 cycles |
| `--all` | Every cycle in INDEX.json |
| `--fail` | Only cycles whose `verdict` is `needs_user` |
| `--grep <text>` | Filter by case-insensitive substring match against `request` |
| `--prune <N>` | After listing, delete history entries beyond the most recent N (and their `<id>-*.json` files). Confirms with the user before deleting. |

Flags can be combined: `/harness-history --fail --grep "schema"` shows failed cycles whose request mentions "schema".

## Output

One line per cycle, newest first. Color verdict if the terminal supports it (green for `complete`, red for `needs_user`).

Format:

```
<id>  <verdict-marker>  <elapsed>  retry <N>   <executors>   "<request>"
```

- `verdict-marker` — `✓` for complete, `✗` for needs_user
- `elapsed` — human form: `47s`, `2m12s`, `14m05s`, `1h 3m`
- `executors` — comma-joined `executors` array from the index entry; if more than 3, show first 2 + `+N more`
- `request` — truncated to 60 chars with `…` if longer

Example output:

```
c-2026-05-18-1432  ✓   2m12s   retry 0   frontend, api          "로그인 버그 수정"
c-2026-05-18-1105  ✗   14m05s  retry 5   ml-pipeline            "데이터 스키마 변경"
c-2026-05-17-2210  ✓   47s     retry 1   frontend               "버튼 색 통일"
```

If `INDEX.json` does not exist, print `No archived cycles yet.` and stop.

If the filter yields zero matches, print `No cycles match the filter.` and stop.

## --prune behavior

When `--prune <N>` is given:

1. Compute the set of entries to delete: everything beyond the most recent N (after applying other filters, if any).
2. Print the list of `<id>` values that would be deleted.
3. Ask the user via `AskUserQuestion`: `Delete these N entries?` with options `Yes` / `Cancel`.
4. On `Yes`: for each `<id>`, remove the matching `<id>-*.json` file from `.harness/history/`, and rewrite `INDEX.json` without those entries.
5. Report the count of deleted entries.

Never delete without confirmation. Never delete the currently-running `state.json` (which is not in INDEX anyway — INDEX only holds terminated cycles).

## Guardrails

- Read-only by default. Only `--prune` writes anything.
- Never modify `state.json` or any `<id>-*.json` files outside the prune flow.
- Do not invoke other slash commands.
