---
description: Render a full timeline of a previously-archived harness cycle from .harness/history/<id>-*.json.
---

Read the archived state.json for a single cycle and print a human-friendly timeline. The data layout is defined in `harness-iterate.md` §1 (state schema) + §8 (archive format).

## Arguments (parse from `$ARGUMENTS`)

| Token | Meaning |
|---|---|
| `<id>` (positional, required) | Cycle id, e.g. `c-2026-05-18-1432`. Prefix matches are accepted if unambiguous (e.g. `c-2026-05-18-14` matches one entry → use it; matches multiple → list them and stop). |
| `--section <name>` | Render only one section: `designer`, `executors`, `attempts`, `verifier`, `rule-applier`, `summary`. Default: all. |
| `--raw` | Dump the raw JSON of `<id>-*.json` instead of formatting. Useful for piping. |
| `--md` | Render as markdown (suitable for paste into PR description / issue / chat). Default is colored terminal. |

## Resolution

1. If `<id>` is missing → print usage and stop.
2. Look in `.harness/history/`. Match files `<id>-complete.json` and `<id>-needs_user.json`. Exactly one of them should exist for a valid id; if neither, report `Cycle <id> not found.` and stop.
3. If `<id>` was a prefix that matched multiple cycles, print them all (one per line) and stop with `Multiple matches; specify a longer prefix.`

## Output (default, full timeline)

```
═══ Cycle <id> ═══
Request:    "<user_request>"
Started:    <cycle_started_at>
Finished:   <finished_at>  (<elapsed>)
Verdict:    <complete | needs_user>  (<termination_reason>)

▸ Designer attempts (<N total>)
    (one entry per item in designer_history)
    Attempt 1:
      decomposition: <executors as bullet list with domain + spec.objective snippet>
      verification picks: [<ids>]
      outcome: <dispatched | escalated | ...>
    Attempt 2:
      ...

▸ Failed attempts (<len(attempt_history)>)         ← omit section if empty
    Attempt <n>: <designer summary>
      → completed_workers: <N changes>
      → verifier_result: <pass | fail · failed checks>
      → failure_reason: <single line>
    Attempt <n+1>: ...

▸ Final executor results
    <executor>   <status>   <N files>   <elapsed>
    <executor>   <status>   <N files>   <elapsed>
    ...
    (from completed_workers — the final, successful or last-tried wave)

▸ Verifier
    Static checks:   <pass | fail | n/a>
    Dynamic checks:
      <id>   <status>   <duration>
      <id>   <status>   <duration>
    Overall:         <pass | fail>
    Notes:           <free-form, if any>

▸ Rule-applier
    <one line per rule applied: name + status>
    <or: skipped — no rule_applier_result, if cycle terminated before finalizing>

▸ Final
    Total elapsed:   <elapsed>
    Termination:     <termination_reason>
    Files changed:   <count if derivable from final completed_workers reports>
```

Section ordering matches phase ordering (designer → executors → verifier → rule-applier) for readability.

## Output (--md mode)

Same content, but:
- Section headers use `## Designer attempts (N)`, etc.
- Tables for executor results, verifier checks, and rule-applier rules.
- No ANSI colors.
- One-shot: useful for paste into PR description, chat, issue body.

## Output (--raw mode)

Cat the contents of `.harness/history/<id>-<verdict>.json` verbatim. Nothing else.

## Output (--section)

Only the named section, with its header. Other sections suppressed.

Valid section names:
- `designer` — designer_history block
- `executors` — final completed_workers block
- `attempts` — attempt_history block (empty if cycle had no failed attempts)
- `verifier` — verifier_result block
- `rule-applier` — rule_applier_result block
- `summary` — top + final stats (no per-attempt detail)

## Guardrails

- Read-only. Never modifies any history file or state.json.
- Do not invoke other slash commands.
- Truncate user_request to ~200 chars in the header if it is unusually long (very long prompts are valid but visually disruptive).
