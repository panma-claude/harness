---
description: Force-activate the harness for the given request, bypassing the auto-activation trigger check.
---

The user has explicitly chosen to run this request through the harness. Trigger evaluation is skipped.

Request:

$ARGUMENTS

Activate the harness now by calling:

```
Skill(skill="loop", args="/harness-iterate $ARGUMENTS")
```

After activation, follow the `harness-orchestration` skill. Initialize `.harness/state.json` for a new cycle (`cycle_id: 1`, `phase: "designing"`, `retry_count: 0`, `user_request` set to the verbatim request above).
