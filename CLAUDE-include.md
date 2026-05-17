# panma-harness — Auto-Activation

When the user's request matches **any** of the triggers below, activate harness mode:

- The request explicitly spans **3 or more** independent concerns (separate areas, modules, or domains as the host project defines them).
- The request requires changes in places that have **separate verification commands** (different build/test entry points).
- The request is naturally **decomposable into chunks that could run in parallel** by different specialists, where each chunk is non-trivial (more than a few minutes of work).
- The user explicitly says "use the harness" or invokes `/harness-start`.

To activate, follow the **activation mode** in `.harness/preferences.yaml` (if file is missing, default `mode: auto`):

### `mode: auto` (default) — silent activation
Call directly:
```
Skill(skill="loop", args="/harness-iterate <user request verbatim>")
```

### `mode: confirm` — show your decision first
1. First, AskUserQuestion summarizing your triage: which triggers matched, what executors might run. Options: `Proceed with harness` (recommended), `Do it directly`, `Cancel`.
2. On `Proceed`: call `Skill(skill="loop", args="/harness-iterate <user request verbatim>")`.
3. On `Do it directly`: handle the request inline as Main, no harness.
4. On `Cancel`: stop.

### `mode: interactive` — confirm + ask verification choice upfront
Same as `confirm`, plus: on `Proceed`, **before** calling `Skill(loop, ...)`, AskUserQuestion about verification:
- `Auto-pick` — let Designer choose from `.harness/verification-checks.yaml` (current default behavior)
- `Manual` — you'll verify the changes yourself; cycle ends with a "please verify" message, no automated dynamic checks
- For each entry in `.harness/verification-checks.yaml`: a checkbox (multiSelect) to pick specific checks
- `Skip dynamic` — run only static cross-cutting checks

Encode the user's pick into the activation args. The convention is a colon-separated suffix:
```
Skill(skill="loop", args="/harness-iterate --verification=<pick> <user request verbatim>")
```
Where `<pick>` is one of: `auto`, `manual`, `none`, or a comma-separated list of check IDs (`ui-smoke,api-contract`). `/harness-iterate` parses this and pre-populates `state.verification_spec` so Designer skips its own picking.

`/harness-iterate` carries the full orchestration protocol (Designer → Executors → Verifier → Rule-Applier, retry budget, worker check-in, termination) in its body. Follow it.

**Do NOT activate for:**

- Single-file edits, one-line fixes, typo corrections.
- Questions / explanations / read-only exploration.
- Requests that are clearly scoped to a single domain.
- Requests where the user has said "do it directly", "no harness", or similar.

When in doubt, prefer **not** to activate. The harness is for genuinely multi-area work; activating it for small tasks adds friction without benefit.
