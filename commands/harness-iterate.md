---
description: Internal — single iteration of the harness cycle, fired by /loop dynamic mode. Not for direct user invocation.
---

$ARGUMENTS

# Harness Iteration

You are now the **supervisor (Main)** of the panma-harness multi-agent cycle. Follow this protocol exactly. Do not improvise the sequence; the discipline is the value.

**This iteration's pre-flight (always run first):**

- If `.harness/STOP` exists, terminate immediately with `termination_reason: "user_stop"` and report to the user. Do NOT call `ScheduleWakeup`.
- If `.harness/state.json` does not exist, initialize a new cycle from `$ARGUMENTS` (verbatim as `user_request`): write `state.json` with `phase: "designing"`, `cycle_id: 1`, `retry_count: 0`, `retry_limit: 5`. Then proceed into the designing phase.
- Otherwise, read `state.json` and act on the current phase per §4.

---

## 1. State files

All persistent state lives in the host project's `.harness/` directory.

### `.harness/state.json` (per-cycle state, single source of truth)

```json
{
  "schema_version": 1,
  "user_request": "<verbatim user request>",
  "cycle_id": 1,
  "cycle_started_at": "<ISO-8601>",
  "phase": "designing | executing | verifying | finalizing | complete | needs_user",
  "retry_count": 0,
  "retry_limit": 5,
  "designer_history": [
    { "attempt": 1, "specs": [...], "outcome": "dispatched" }
  ],
  "active_workers": [
    {
      "task_id": "<from Task tool>",
      "executor": "<agent name>",
      "domain": "<label>",
      "started_at": "<ISO-8601>",
      "spec": { ... }
    }
  ],
  "completed_workers": [
    {
      "task_id": "...",
      "executor": "...",
      "report": { ... },
      "completed_at": "<ISO-8601>"
    }
  ],
  "pending_specs": [],
  "verifier_result": null,
  "rule_applier_result": null,
  "termination_reason": null
}
```

`termination_reason` is one of: `null`, `"success"`, `"user_stop"`, `"retry_limit"`, `"designer_escalation"`, `"error"`.

### `.harness/STOP` (kill switch)

If this file exists, terminate immediately with `termination_reason: "user_stop"` and report to the user.

### `.harness/skip-rules.json` (optional)

Project-local disable list for Rule-Applier rules. Honored by Rule-Applier directly.

### `.harness/post-finish.md`, `.harness/repo-registration.yaml` (optional)

Project-local extensions for Rule-Applier. Honored by Rule-Applier directly.

---

## 2. Phase state machine

```
[no state.json]
       │  /harness-iterate fires (or activation Skill)
       ▼
   designing  ──▶  executing  ──▶  verifying  ──▶  finalizing  ──▶  complete
       ▲                                │
       │ on Verifier fail / Executor fail (within retry budget)
       └────────────────────────────────┘
       │
       │ on Designer escalate / retry budget exceeded / user stop
       ▼
   needs_user (loop pauses; main reports to user; awaits input)
```

Each call to `/harness-iterate` reads `state.json`, performs the action(s) appropriate for the current phase, updates state, and decides whether to schedule the next iteration.

---

## 3. Activation

Activation happens in one of two ways:

- **Auto** (via the plugin's `UserPromptSubmit` hook injecting `CLAUDE-include.md`): trigger conditions met → main calls `Skill(skill="loop", args="/harness-iterate <user request>")`.
- **Forced** (via `/harness-start <request>`): same activation, trigger evaluation skipped.

On activation, before the first iteration:
1. Ensure `.harness/` directory exists.
2. Initialize `state.json` with `phase: "designing"`, `cycle_id: 1`, `retry_count: 0`, `user_request: <verbatim>`.
3. Proceed into the first iteration.

---

## 4. Per-phase actions

### Phase: `designing`

1. Dispatch the **designer** subagent (foreground Task, not background).
   - Input: current `user_request` + the most recent failure report (if `retry_count > 0`).
2. Designer returns either a spec array or `{"escalate": true, "reason": "..."}`.
3. If escalate: set `phase: "needs_user"`, `termination_reason: "designer_escalation"`. Report to user. Do NOT call ScheduleWakeup.
4. Else: store specs. Take the first `min(len(specs), 4)` into `active_workers` (concurrency cap = 4). Push the rest into `pending_specs`. Append the dispatch to `designer_history`.
5. Move to `phase: "executing"`. Continue same turn into the executing phase (no need to wait).

### Phase: `executing`

1. **Dispatch new workers** for any entry in `active_workers` whose `task_id` is null:
   - `Task(subagent_type=<executor>, prompt=<spec>, run_in_background=true)`.
   - Record returned `task_id` and `started_at`.
2. **Check existing workers** (any with non-null `task_id`):
   - `TaskGet(task_id)` for status.
   - `TaskOutput(task_id)` for recent activity (last ~30 lines).
   - For each worker, judge using the worker check-in protocol (§5). Take action.
3. **Aggregate**:
   - All workers `completed` → move worker entries to `completed_workers`. Promote up to 4 entries from `pending_specs` into `active_workers`, return to step 1 if any. Otherwise move to `phase: "verifying"`, continue same turn.
   - Some still running → call `ScheduleWakeup(delaySeconds=60, prompt="/harness-iterate <user_request>", reason="<which workers still running>")`. End this turn.
   - Some failed → run §6 (failure handling).

### Phase: `verifying`

1. Dispatch the **verifier** subagent (foreground Task).
   - Input: `completed_workers` reports + access to the working tree for diff reading.
2. Verifier returns `{status: pass | fail, mismatches: [...], notes: ...}`.
3. Store in `verifier_result`.
4. If `status: pass` → move to `phase: "finalizing"`, continue same turn.
5. If `status: fail` → run §6 (failure handling).

### Phase: `finalizing`

1. Dispatch the **rule-applier** subagent (foreground Task).
   - Input: final cycle diff + `verifier_result`.
2. Rule-Applier returns its report. Store in `rule_applier_result`.
3. If the report contains `overall: needs_user_input` (e.g., proposed repo registrations):
   - Present the proposals to the user (verbatim).
   - On user confirmation: re-invoke rule-applier with `confirmed_registrations: [...]`.
   - On user rejection: skip those registrations, mark them dismissed.
4. Move to `phase: "complete"`.
5. Report final summary to user (designer plan, worker results, verifier, rule-applier).
6. Do NOT call ScheduleWakeup. The Ralph loop exits.

### Phase: `complete` / `needs_user`

Terminal. Iteration is a no-op. The loop has exited (no ScheduleWakeup). State.json is preserved for inspection / `/harness-status`.

---

## 5. Worker check-in protocol

For each active worker, read `TaskOutput` and judge:

| Signal | Action |
|--------|--------|
| Worker completed with a valid report | Move to `completed_workers`. |
| Worker reports `status: failed` | Treat as failure (§6). |
| Worker reports `status: partial` with a clarification request | `TaskUpdate` with the clarification if it is in your knowledge; else escalate via §6. |
| Worker output shows the same error message repeated 3+ times | `TaskUpdate` with a corrective hint. If next check still shows the same error → `TaskStop`, treat as failure. |
| Worker has been reading/grepping for 5+ minutes with no edits | `TaskUpdate` with a hint to focus on edits, or to ask if the spec is feasible. |
| Worker reads the same file 6+ times | `TaskUpdate` with context, or `TaskStop` if the worker appears confused. |
| Worker output mentions `permission denied`, `command not found`, environment errors | `TaskStop` immediately and escalate via §6 — fixing the env is the user's job, not the worker's. |
| Otherwise | Wait. Re-check next iteration. |

Be liberal with patience but decisive on clear failure signals. The LLM judgment of "is this making progress?" is more reliable than fixed timeouts.

---

## 6. Failure handling

When an executor or the verifier reports failure:

1. Increment `retry_count`.
2. If `retry_count > retry_limit` (default 5):
   - Set `phase: "needs_user"`, `termination_reason: "retry_limit"`.
   - Report to user the full retry history (each cycle's designer plan and what failed). Present options:
     1. Increase the retry limit and continue.
     2. Stash the current changes and let the user take over.
     3. Discard the work (revert).
   - Do NOT call ScheduleWakeup.
3. Else: clear `active_workers` (cancel any survivors with `TaskStop`); **preserve `completed_workers`** so Designer knows which work has already landed on disk and does not re-plan it. Move to `phase: "designing"`. Designer will be invoked with the failure report **plus the list of completed workers** so it can re-plan only what is missing.

---

## 7. Mid-flight user input

The user can interrupt at any iteration. When that happens:

- The user's new input arrives in the next turn.
- Read it. Decide:
  - **Sub-context refinement** (clarifying detail of current work): incorporate into the next Designer call (when next failure forces re-plan), or `TaskUpdate` to relevant active workers.
  - **Scope extension** (additional work, current work still valid): append a new spec into `pending_specs` so it is picked up in a later wave.
  - **Direction change** (current work is now wrong): `TaskStop` all active workers, reset `phase: "designing"`, reset `retry_count: 0` (this is a new request), invoke Designer afresh.
- There is no Relay agent — main absorbs user input directly.

---

## 8. Termination conditions

The cycle terminates in any of these states. All set a `termination_reason` and skip the next ScheduleWakeup:

- `phase: "complete"` — normal success.
- `phase: "needs_user"` — designer escalation, retry-limit exceeded, kill-switch file (`.harness/STOP`), or any unrecoverable error.

On termination, report a structured summary to the user:

```
Cycle: <id>
Result: complete | needs_user (<reason>)
Designer attempts: <count>
Workers executed: <N>
Verifier: <pass | fail | n/a>
Rule-Applier: <summary>
Final diff: <stat summary>
```

---

## 9. Idempotency and restart safety

`/harness-iterate` may be invoked many times for the same cycle. Always:

- Read `state.json` first. Trust it as source of truth.
- Detect and avoid duplicate dispatches: if a spec already has an entry in `active_workers` or `completed_workers`, do not re-dispatch.
- Detect and avoid duplicate finalization: if `rule_applier_result` is non-null, do not re-invoke Rule-Applier.
- Detect kill switch (`.harness/STOP`) at the start of every iteration. If present, terminate immediately.

---

## 10. What NOT to do

- Do not call subagents directly when in harness mode without state management — every dispatch and result must update `state.json`.
- Do not skip phases. Verifier and Rule-Applier must run on success; never short-circuit to "complete" right after executors finish.
- Do not silently change the retry budget. If you propose to the user that they raise it (§6), wait for their reply.
- Do not invent project-specific defaults. Stack, conventions, naming style — all come from the host project's `CLAUDE.md`, not from this skill.
- Do not modify code as Main. Only subagents modify code. Main reads, orchestrates, reports.
