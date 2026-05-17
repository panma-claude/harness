---
description: Force-stop the harness cycle. Stops active workers and prevents further iterations.
---

Terminate the harness cycle immediately:

1. Create `.harness/STOP` (touch the file). The next `/harness-iterate` will see it and bail.
2. For every entry in `state.json`'s `active_workers`, call `TaskStop(task_id)`.
3. Update `state.json`: set `phase: "needs_user"`, `termination_reason: "user_stop"`.
4. Do NOT call `ScheduleWakeup`. The Ralph loop will exit on the next iteration.
5. Report to the user what was stopped and the current diff state (if any worker had begun editing).

After stop, the user can:
- Inspect with `/harness-status`.
- Resume with `/harness-start` (clears `.harness/STOP` and starts a new cycle).
- Reset retry counter with `/harness-reset` (preserves state but zeros `retry_count`).
