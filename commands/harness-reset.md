---
description: Zero the retry counter for the current cycle without stopping it. Useful after asking the user to raise the retry budget.
---

Reset the harness retry counter and clear any pending re-plan state:

1. Read `.harness/state.json`.
2. Set `retry_count: 0`.
3. Clear `active_workers` and `completed_workers` for the current phase (so the next iteration starts fresh).
4. If `phase` was `"needs_user"` because of retry-limit exhaustion, set `phase: "designing"` so the Designer is invoked again on the next iteration.
5. Remove `.harness/STOP` if present.
6. Write state back.
7. Report to the user: `Retry counter reset. Cycle <id> resuming at phase: designing.`

If no state.json exists, report `No harness cycle to reset.` and do nothing.

Note: `/harness-reset` does not change `cycle_id` or `user_request`. It is a soft reset, not a new cycle. For a fully new cycle, use `/harness-start` with a new request.
