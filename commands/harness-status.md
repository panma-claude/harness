---
description: Report the current state of the harness cycle from .harness/state.json, or the most recently archived cycle if none is in progress.
---

Read `.harness/state.json` (if it exists) and produce a compact status report:

```
Cycle:           <cycle_id>
Phase:           <phase>
Started:         <cycle_started_at>
Retry:           <retry_count> / <retry_limit>
Designer:        <attempts so far>
Active workers:  <N>  (list executor + elapsed for each)
Completed:       <N>  (list executor + status for each)
Verifier:        <pass | fail | n/a>
Rule-Applier:    <summary | n/a>
Termination:     <reason | running>
Kill switch:     <present | absent>  (.harness/STOP)
Queue depth:     <len(pending_specs)>
Failed attempts: <len(attempt_history)>   (if > 0; otherwise omit)
```

If no `state.json` exists, fall back to `.harness/history/INDEX.json` and report the most recent cycle in one line:

```
No harness cycle in progress.
Last cycle: <id>  <verdict>  retry <retry_count>  "<request>"  (<elapsed>, finished <ago>)
For details: /harness-replay <id>
```

If neither `state.json` nor `INDEX.json` exists, report `No harness cycle in progress.` and stop.
