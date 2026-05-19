---
description: Internal — single iteration of the harness cycle, fired by /loop dynamic mode. Not for direct user invocation.
---

$ARGUMENTS

# Harness Iteration

You are now the **supervisor (Main)** of the panma-harness multi-agent cycle. Follow this protocol exactly. Do not improvise the sequence; the discipline is the value.

**This iteration's pre-flight (always run first):**

- If `.harness/STOP` exists, terminate immediately with `termination_reason: "user_stop"`. If `state.json` exists, **archive (see §8)** before removing it; also remove `.harness/STOP`. Report to the user. Do NOT call `ScheduleWakeup`.
- If `.harness/state.json` exists but its `phase` is `complete` or `needs_user` (i.e., a stale archive from a previous cycle that wasn't cleaned up — should not normally happen because termination archives + deletes, see §8): archive it to `.harness/history/` as if terminating now (append to `INDEX.json`, write `<id>-<verdict>.json`), then delete it. Treat this as the "state.json does not exist" branch below.
- If `.harness/state.json` does not exist, initialize a new cycle from `$ARGUMENTS`:
  - Strip any leading `--verification=<pick>` flag and capture the value (see below); the rest of `$ARGUMENTS` becomes `user_request` verbatim.
  - Write `state.json` with `phase: "designing"`, `cycle_id: 1`, `retry_count: 0`, `retry_limit: 5`, `attempt_history: []`.
  - Set `verification_spec` based on the captured flag:
    - `--verification=auto` (or no flag) → `[]` (Designer will pick later)
    - `--verification=manual` → `["manual"]` sentinel; Verifier will skip its dynamic phase and the cycle ends with a "please verify" message
    - `--verification=none` → `[]` AND set `state.verification_user_skip: true` so Designer knows not to re-pick (vs auto where Designer does pick)
    - `--verification=<id-1>,<id-2>` → `["<id-1>", "<id-2>"]`; Designer will use this as-is and not re-pick
  - Then proceed into the designing phase.
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
  "verification_spec": [],
  "verification_ephemeral": [],
  "verifier_result": null,
  "rule_applier_result": null,
  "termination_reason": null,
  "attempt_history": [
    {
      "attempt": 1,
      "designer_spec": { ... },
      "completed_workers": [...],
      "verifier_result": { ... },
      "failure_reason": "<one-line summary>"
    }
  ]
}
```

`attempt_history` accumulates one entry per **failed** re-plan attempt within this cycle. On Verifier or Executor failure within retry budget, the current attempt's snapshot (designer spec, completed workers, verifier result, single-line failure reason) is pushed before `active_workers`/`completed_workers` are cleared for the next re-plan. The successful (final) attempt is reflected in the live `completed_workers` + `verifier_result` fields and is **not** duplicated into `attempt_history`. This array is the cycle's failure trail; it is the data `/harness-replay` renders as the per-attempt timeline.

**Compression rule.** To bound `state.json` size on cycles that retry many times, middle entries in `attempt_history` are compressed at push time: only the first entry and the most recent entry stay rich (with `designer_spec`, `completed_workers`, `verifier_result`); everything between is reduced to `{attempt, failure_reason}` alone. See §6 for the mechanics. The rule is: first attempt and the last (current) attempt are always full; older entries between them are compressed. `/harness-replay` renders compressed entries with a `(compressed)` marker — sufficient for "what failed and why" overview, while preserving the first-failure context and the most-recent-failure context in full.

`verification_spec` is the list of check IDs Verifier will execute in its dynamic phase. Each entry is either:
- a string id referring to an entry in `.harness/verification-checks.yaml`, or
- the sentinel `"manual"` (when user opted to verify themselves; Verifier skips dynamic phase entirely).

It is set in one of three ways:
- Designer picks from `.harness/verification-checks.yaml` during designing (default `auto` flow), plus user-promoted candidates from the cycle-start picker (§4 designing).
- Pre-populated from `--verification=<pick>` activation arg when the user chose explicitly via the interactive mode (Designer skips picking and the candidate picker is skipped).
- Sentinel `["manual"]` — user opted to verify themselves; the cycle's final report includes a "please verify" prompt with the changed files.

`verification_ephemeral` is the list of one-shot checks the user chose to run *this cycle only* (not persisted to yaml). Each entry is a full inline check object `{id, cmd, applicable_when, timeout}`. Verifier executes these in addition to the yaml-resolved `verification_spec` entries. Cleared on cycle termination.

`verification_user_skip` (optional bool) — when true, both Designer and Verifier treat the empty `verification_spec` as "user said skip", not "no checks defined".

`termination_reason` is one of: `null`, `"success"`, `"user_stop"`, `"retry_limit"`, `"designer_escalation"`, `"error"`.

### `.harness/STOP` (kill switch)

If this file exists, terminate immediately with `termination_reason: "user_stop"` and report to the user.

### `.harness/skip-rules.json` (optional)

Project-local disable list for Rule-Applier rules. Honored by Rule-Applier directly.

### `.harness/post-finish.md`, `.harness/repo-registration.yaml` (optional)

Project-local extensions for Rule-Applier. Honored by Rule-Applier directly.

### `.harness/verification-checks.yaml` (optional)

Project-local library of runtime verification checks (api-contract, ui-smoke, playwright e2e, etc.). Read by Designer to pick per-cycle `verification_spec`, then executed by Verifier in its dynamic phase. Honored by Designer and Verifier directly.

### `.harness/verifier-progress.json` (transient, optional)

Written by the **verifier** subagent before each dynamic check in Phase 2. Read by panma-hud's statusline to show live verifier progress. Shape:

```json
{
  "current": "<check-id>",
  "started_at": "<ISO-8601>",
  "completed": ["<id-1>", "<id-2>"],
  "total": <N>
}
```

Cleaned up by Main at the archive step (§8). Should be in `.gitignore`.

### `.harness/rule-applier-progress.json` (transient, optional)

Written by the **rule-applier** subagent before each finalization step (review, security-review, each post-finish rule, repo-registration). Same shape as verifier-progress. Read by panma-hud's statusline to show live finalizing progress. Cleaned up by Main at the archive step (§8). Should be in `.gitignore`.

### `.harness/history/` (cycle archive)

When a cycle terminates (success or `needs_user`), its final `state.json` is archived here and the live `state.json` is removed so the next user request starts a fresh cycle. Two files are written per terminated cycle:

- `<id>-<verdict>.json` — full snapshot of the final `state.json`. `<id>` is `c-YYYY-MM-DD-HHMM` (derived from `cycle_started_at`); `<verdict>` is one of `complete`, `needs_user`. Example: `.harness/history/c-2026-05-18-1432-complete.json`.
- `INDEX.json` — a single JSON array of summary entries, appended on each archive. Each entry:
  ```json
  {
    "id": "c-2026-05-18-1432",
    "verdict": "complete",
    "termination_reason": "success",
    "request": "<verbatim user_request>",
    "executors": ["frontend", "api"],
    "retry_count": 0,
    "started_at": "<cycle_started_at ISO-8601>",
    "finished_at": "<termination ISO-8601>",
    "elapsed_sec": 132
  }
  ```

`INDEX.json` is the cheap listing surface — `/harness-history` reads only this file. Detailed timelines (`/harness-replay <id>`) read the corresponding `<id>-*.json`. The archive directory should be added to `.gitignore` (it is local runtime state, like `state.json` itself).

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
2. Initialize `state.json` with `phase: "designing"`, `cycle_id: 1`, `retry_count: 0`, `attempt_history: []`, `user_request: <verbatim>`.
3. Proceed into the first iteration.

---

## 4. Per-phase actions

### Phase: `designing`

1. Dispatch the **designer** subagent (foreground Task, not background).
   - Input: current `user_request` + the most recent failure report (if `retry_count > 0`) + a flag indicating whether `verification_spec` is already populated.
   - If `verification_spec` is already populated (from a `--verification=` activation arg, including the `["manual"]` sentinel), tell Designer to **skip** verification picking AND skip the candidate-suggestion step. Designer should emit only `{"executors": [...]}`.
2. Designer returns either a `{"executors": [...], "verification": [...], "verification_candidates": [...]}` object or `{"escalate": true, "reason": "..."}`. Tolerate the legacy plain-array form by treating it as `{executors: <array>, verification: [], verification_candidates: []}`. The `verification_candidates` field is optional and may be absent or empty.
3. If escalate: set `phase: "needs_user"`, `termination_reason: "designer_escalation"`. **Archive (see §8)** then report to user. Do NOT call ScheduleWakeup.
4. Else: store specs. Take the first `min(len(executors), 4)` into `active_workers` (concurrency cap = 4). Push the rest into `pending_specs`. If `verification_spec` is still empty AND Designer returned a `verification` list, store it. If `verification_spec` was already populated from activation, keep it as-is — Designer's picks are ignored. Append the dispatch to `designer_history`.
5. **Run the candidate picker** (§4-candidate-picker) if all of: (a) this is the first design attempt (`retry_count == 0`), (b) `verification_spec` was NOT pre-populated from activation, (c) `verification_user_skip` is not true, (d) Designer returned a non-empty `verification_candidates` list. Otherwise skip.
6. Move to `phase: "executing"`. Continue same turn into the executing phase (no need to wait).

### §4-candidate-picker: present new verification suggestions to the user

The picker turns Designer's `verification_candidates` into a 3-way user decision per candidate. It runs once, in the first design pass of a cycle, **regardless of `mode:` in preferences.yaml** — verification is too consequential to skip on auto mode.

Steps:

1. **Build the question batch.** For each candidate (cap at 4 per batch — split into multiple `AskUserQuestion` calls if more), create one question:

   - `question`: `"<candidate.id> 검증 — <candidate.rationale> (cmd: <truncated cmd, <FILL: ...> shown verbatim>)"`
   - `header`: short label, e.g. `"backend build"` (≤12 chars; truncate id if needed)
   - `multiSelect`: false
   - `options`:
     - `{ label: "이번만 실행", description: "이 cycle 의 Verifier 가 실행. yaml 미수정." }`
     - `{ label: "yaml 영구 등록", description: "verification-checks.yaml 에 append + 이번 cycle 도 실행. 미래 cycle 자동." }`
     - `{ label: "skip", description: "이번 cycle 미실행, yaml 미수정." }`

   Order the candidates with `source: "auto"` first (cleaner cmd, easier to accept), `source: "fill_needed"` last.

2. **Pick the default option for each candidate.** Set the first option (the recommended default that AskUserQuestion shows first) based on `source`:
   - `auto` → put `"yaml 영구 등록"` first (recommended)
   - `fill_needed` → put `"skip"` first (cmd needs filling before it can run; user must promote intentionally)

3. **Collect answers.** Iterate the batches; each `AskUserQuestion` call returns the user's selection per question.

4. **Apply selections.** For each candidate, based on the answer:

   - **"yaml 영구 등록"**: append the candidate as a new entry to `.harness/verification-checks.yaml` under `checks:`. Use the candidate's `id`, `cmd`, `applicable_when`, `timeout`. Add a one-line comment above the entry: `# added by harness-iterate cycle <cycle_id> on <ISO date>`. Create the file with a top-level `checks:` key if it does not exist. De-dup by `id` (skip silently if id already present). Also push the `id` into `verification_spec` so this cycle runs it.

   - **"이번만 실행"**: do NOT modify yaml. Push the full inline check object `{id, cmd, applicable_when, timeout}` into `verification_ephemeral` (a new state.json field — see §1). Verifier will execute these in its dynamic phase in addition to the `verification_spec` entries.

   - **"skip"**: do nothing.

5. **Validate `<FILL: ...>` placeholders.** Before persisting/executing, scan each chosen candidate's `cmd` for the pattern `<FILL:`. If found:
   - If user chose **"이번만 실행"** or **"yaml 영구 등록"**, surface a single-line warning to the user (`AskUserQuestion` follow-up with one question: "<id>: cmd 가 placeholder 입니다. 직접 채우러 가시겠습니까?" with options `[Yes, 채우러 가기 — yaml 열기 / Just skip this cycle / Persist as-is]`). The Yes path opens the yaml in the user's editor (best-effort — just print the path; user opens it).
   - On `"Just skip"`, undo the apply for this candidate.
   - On `"Persist as-is"`, keep the placeholder. Verifier will skip the check at runtime (placeholder cmd does not execute).

6. **Update state.json.** Persist the new `verification_spec`, `verification_ephemeral`, and (if any) the on-disk yaml change. Proceed to step 6 of the parent flow (move to executing).

The picker is **not** a phase. It's a sub-step of designing that runs once per cycle, synchronously, before executors dispatch.

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
   - Input: `completed_workers` reports + access to the working tree + the current `verification_spec` + `verification_ephemeral`.
   - Verifier resolves `verification_spec` ids against `.harness/verification-checks.yaml` (standard path) AND additionally runs every check object in `verification_ephemeral` inline (id, cmd, applicable_when, timeout supplied directly — no yaml lookup). Skip any check whose `cmd` contains `<FILL:` — emit `status: skipped_placeholder` for that entry.
   - If `verification_spec` is `["manual"]`, tell Verifier to run **only** its static phase and emit `dynamic_checks: []` with a `status: deferred_to_user` note in `notes`. Verifier still executes the 6 static cross-cutting checks; that part is not optional. `verification_ephemeral` is ignored in manual mode.
2. Verifier returns `{status: pass | fail, mismatches: [...], dynamic_checks: [...], notes: ...}`.
3. Store in `verifier_result`.
4. If `status: pass` → move to `phase: "finalizing"`, continue same turn.
5. If `status: fail` → run §6 (failure handling). The failure report passed back to Designer must include both `mismatches` and any failed `dynamic_checks` so it can decide whether to re-decompose, change the verification picks, or escalate.

### Phase: `finalizing`

1. Dispatch the **rule-applier** subagent (foreground Task).
   - Input: final cycle diff + `verifier_result` + `verification_ephemeral` (so it can suggest promotions) + the project's auto-memory directory path if your context shows one (Main has it via the auto-memory system reminder; pass the absolute `memory/` dir path and the absolute `MEMORY.md` path so Rule-Applier can de-dup against existing memories). Omit these inputs if auto-memory is not wired in this session.
2. Rule-Applier returns its report. Store in `rule_applier_result`.
3. If the report contains `overall: needs_user_input` (e.g., proposed repo registrations):
   - Present the proposals to the user (verbatim).
   - On user confirmation: re-invoke rule-applier with `confirmed_registrations: [...]`.
   - On user rejection: skip those registrations, mark them dismissed.
4. If `rule_applier_result.verification_promotion` is non-empty, include a short suggestion section in the final summary listing those ids and a note: "다음 cycle 의 candidate picker 에서 동일 항목을 'yaml 영구 등록' 으로 선택하면 자동 추가됩니다." Do not prompt now — surfacing once is enough.
5. **Handle memory candidates** (§4-memory-candidates) if `rule_applier_result.memory_candidates` is non-empty. Run regardless of `mode:` in preferences.yaml (memory write is consequential enough to confirm, but bounded to 1 prompt — the trigger gates already ensure most cycles emit zero candidates).
6. Move to `phase: "complete"`.
7. Report final summary to user (designer plan, worker results, verifier, rule-applier, verification promotion suggestions, memory write result if any).

### §4-memory-candidates: handle proposed memory writes

The candidate is shaped `{slug, type, title, body, why, how_to_apply}`. For each (typically 1 max):

1. **Check auto-memory is wired in this session.** Look at your own system context for an auto-memory directory path. If absent, skip the prompt; instead emit a single advisory line in the final summary: `Memory candidate '<slug>' suggested — auto-memory not configured for this project, save manually if desired.` Include the candidate body in the advisory so the user can copy it.

2. **Prompt the user via AskUserQuestion** (one question per candidate, single-select):
   - `question`: `"Lesson 발견: <title>\n  Body: <body>\n  Why: <why>\n  How to apply: <how_to_apply>\n  메모리에 저장할까요? (slug: <slug>, type: <type>)"`
   - `header`: `"메모리 후보"` (≤12 chars)
   - `multiSelect`: false
   - `options`:
     - `{ label: "Yes, 저장", description: "<auto-memory-dir>/<slug>.md 작성 + MEMORY.md 에 한 줄 추가." }`
     - `{ label: "Skip", description: "이번에는 저장하지 않음. 후속 cycle 에서 다시 제안될 수 있음." }`
     - `{ label: "Show path, I'll edit", description: "메모리 경로만 출력. 내가 직접 작성." }`

3. **Apply the answer:**

   - **Yes, 저장:**
     1. Write `<auto-memory-dir>/<slug>.md` with the frontmatter format dictated by Claude Code's auto-memory system:
        ```markdown
        ---
        name: <slug>
        description: <title>
        metadata:
          type: <type>
        ---

        <body>

        **Why:** <why>

        **How to apply:** <how_to_apply>
        ```
        Refuse to overwrite an existing file with the same slug — if it exists, fall through to "Show path" path with a note.
     2. Append a one-line index entry to `<MEMORY.md>`:
        `- [<title>](<slug>.md) — <one-line hook derived from body>`
     3. Record in `rule_applier_result.memory_write: {status: "saved", slug, path}`.

   - **Skip:**
     - Record in `rule_applier_result.memory_write: {status: "skipped", slug}`. Do nothing else.

   - **Show path, I'll edit:**
     - Print the proposed file path (`<auto-memory-dir>/<slug>.md`) and the full frontmatter+body as a code block in the final summary. User saves it themselves.
     - Record `{status: "deferred_to_user", slug, path}`.

4. **Idempotency.** If `rule_applier_result.memory_write` is already set (e.g., re-entering finalizing after partial completion), skip this step entirely.

---

Resuming the main finalizing flow after §4-memory-candidates:

8. **If `verification_spec` was `["manual"]`**, append a "Please verify" block to the final summary:
   ```
   Verification deferred to you.
   Changed files (N):
     - <path>
     - <path>
     ...
   Please verify manually (browser, smoke command, whatever fits) and let me know if anything looks wrong.
   ```
9. Set `phase: "complete"`, `termination_reason: "success"`.
10. **Archive (see §8)** — ships the cycle to `.harness/history/` and deletes `state.json`.
11. Do NOT call ScheduleWakeup. The Ralph loop exits.

### Phase: `complete` / `needs_user`

Terminal. Iteration is a no-op. Under normal operation `state.json` has already been archived and removed at the moment of termination (see §8), so this branch only fires when the archive step was skipped or interrupted. In that case, archive + remove `state.json` here as a safety net, then exit.

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
   - First push the latest failure into `attempt_history` using the same push helper as step 3.1 (which also compresses the prior last entry — see §6-push-attempt). The limit-exceeding attempt must be captured before termination.
   - Set `phase: "needs_user"`, `termination_reason: "retry_limit"`.
   - **Archive (see §8)** so `attempt_history` is preserved for `/harness-replay`.
   - Report to user the full retry history (each cycle's designer plan and what failed; pull this from `attempt_history` rather than relying on context, since the archive is now authoritative). Present options:
     1. Increase the retry limit and continue.
     2. Stash the current changes and let the user take over.
     3. Discard the work (revert).
   - Do NOT call ScheduleWakeup.
3. Else, snapshot the failed attempt then re-plan:
   1. **Push to `attempt_history`** using the helper in §6-push-attempt (BEFORE clearing anything). The new entry is full; the previous last entry, if it was full, gets compressed at this moment.
   2. Clear `active_workers` (cancel any survivors with `TaskStop`).
   3. **Preserve `completed_workers`** so Designer knows which work has already landed on disk and does not re-plan it.
   4. Move to `phase: "designing"`. Designer will be invoked with the failure report **plus the list of completed workers** so it can re-plan only what is missing.

### §6-push-attempt: bounded-size attempt_history push helper

Both push sites above use this procedure:

1. Build the **new full entry**:
   ```json
   {
     "attempt": <current retry_count, pre-increment value — so the first failure is attempt 1>,
     "designer_spec": <last entry in designer_history>,
     "completed_workers": <current completed_workers array>,
     "verifier_result": <current verifier_result, may be null if executor failed first>,
     "failure_reason": "<single-line summary: verifier mismatch / dynamic_check id / executor error>"
   }
   ```
2. **Compress the previous last entry, if any.** If `attempt_history` already contains 2 or more entries, the entry currently at `attempt_history[-1]` is about to become a middle entry. Replace it in place with its compressed form:
   ```json
   { "attempt": <its attempt number>, "failure_reason": <its failure_reason> }
   ```
   Drop the `designer_spec`, `completed_workers`, `verifier_result` fields entirely. (If `attempt_history` has 0 or 1 entries, skip compression — the first entry must always stay full.)
3. Append the new full entry to `attempt_history`.

Result: after every push, `attempt_history` has the shape `[first_full, mid_compressed, mid_compressed, ..., last_full]`. On the first failure, just `[first_full]`. On the second, `[first_full, second_full]` (no compression possible yet). From the third onward, compression kicks in.

This is idempotent and stable under restart: re-reading `state.json` mid-cycle and resuming pushes uses the same logic; entries already compressed stay compressed (their `designer_spec` etc. are already missing, so the compression step is a no-op on them).

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

### Archive step (call once per cycle, at every termination path)

Before reporting the summary, archive the cycle so it survives the next request:

1. Derive `id` from `cycle_started_at`: format `c-YYYY-MM-DD-HHMM` (UTC). Example: `c-2026-05-18-1432`. If two cycles in the same minute collide (rare), append `-2`, `-3`, etc.
2. Derive `verdict`: `"complete"` if `phase == "complete"`, else `"needs_user"`.
3. Compute `finished_at` (now, ISO-8601) and `elapsed_sec` (`finished_at - cycle_started_at`).
4. Write the full current `state.json` content to `.harness/history/<id>-<verdict>.json`. Create the `.harness/history/` directory if missing.
5. Append a summary entry to `.harness/history/INDEX.json` (create as `[]` if missing):
   ```json
   {
     "id": "<id>",
     "verdict": "<verdict>",
     "termination_reason": "<from state.json>",
     "request": "<user_request truncated to ~200 chars>",
     "executors": ["<domain or executor for each entry in completed_workers>"],
     "retry_count": <from state.json>,
     "started_at": "<cycle_started_at>",
     "finished_at": "<finished_at>",
     "elapsed_sec": <elapsed>
   }
   ```
   Append, do not rewrite the whole array — read existing, push, write back.
6. **Delete `.harness/state.json`** so the next user request starts a fresh cycle.
7. **Delete transient progress files** if present: `.harness/verifier-progress.json`, `.harness/rule-applier-progress.json`. They are mid-run state and have no value after the cycle ends (the archived state.json + verifier_result / rule_applier_result are the authoritative summary).

If archive fails (disk full, permission denied, etc.), still report the summary to the user — never leave them in the dark — but include a single line noting the archive failure and the original `state.json` path so they can keep it manually.

### Summary report

After archiving, report to the user:

```
Cycle: <id>
Result: complete | needs_user (<reason>)
Designer attempts: <count>
Workers executed: <N>
Verifier: <pass | fail | n/a>
Rule-Applier: <summary>
Final diff: <stat summary>
Archived: .harness/history/<id>-<verdict>.json
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
