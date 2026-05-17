---
description: Report the current state of the harness cycle from .harness/state.json.
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
```

If no `state.json` exists, report `No harness cycle in progress.`
