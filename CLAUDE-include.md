# panma-harness — Auto-Activation

When the user's request matches **any** of the triggers below, activate harness mode:

- The request explicitly spans **3 or more** independent concerns (separate areas, modules, or domains as the host project defines them).
- The request requires changes in places that have **separate verification commands** (different build/test entry points).
- The request is naturally **decomposable into chunks that could run in parallel** by different specialists, where each chunk is non-trivial (more than a few minutes of work).
- The user explicitly says "use the harness" or invokes `/harness-start`.

To activate, call:

```
Skill(skill="loop", args="/harness-iterate <user request verbatim>")
```

`/harness-iterate` carries the full orchestration protocol (Designer → Executors → Verifier → Rule-Applier, retry budget, worker check-in, termination) in its body. Follow it.

**Do NOT activate for:**

- Single-file edits, one-line fixes, typo corrections.
- Questions / explanations / read-only exploration.
- Requests that are clearly scoped to a single domain.
- Requests where the user has said "do it directly", "no harness", or similar.

When in doubt, prefer **not** to activate. The harness is for genuinely multi-area work; activating it for small tasks adds friction without benefit.
