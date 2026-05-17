---
description: Single iteration of the harness cycle. Fired by /loop dynamic mode; not intended for direct user use.
---

$ARGUMENTS

Apply the `harness-orchestration` skill. Read `.harness/state.json` to determine the current phase, perform that phase's actions, update state, and decide whether to schedule the next iteration via `ScheduleWakeup`.

If `.harness/STOP` exists, terminate immediately and report to the user.

If `state.json` does not exist, initialize a new cycle using the request above (`$ARGUMENTS`) and begin in `phase: "designing"`.
