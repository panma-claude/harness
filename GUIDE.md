# panma-harness — Guide

This guide is the single source of truth for **using** the harness. It assumes you know what [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) is and that you can install/edit files in a project.

Three sections matter most:

- **[Quick install](#quick-install)** — get the harness running in any project in 30 seconds.
- **[Level 1: domain executors](#level-1-domain-executors)** — the main customization most projects want.
- **[Troubleshooting](#troubleshooting)** — when something behaves unexpectedly.

The rest is reference material for when you need deeper control.

---

## What it is

A multi-agent supervisor for Claude Code. When the user asks for work that spans multiple independent areas of a project, the harness:

1. **Decomposes** the request into per-area specifications (Designer).
2. **Dispatches** specialized subagents in parallel to do the work (Executors).
3. **Verifies** that the parallel changes are internally consistent (Verifier).
4. **Finalizes** with review, security, and optional repo registration (Rule-Applier).
5. **Iterates** until the work is done or a retry budget is exhausted.

The supervisor is just Claude Code itself, executing a strict orchestration protocol loaded from a skill. There is no separate runtime.

Stack-agnostic by design. What constitutes a "domain" is whatever the host project decides — backend / frontend / data, or service-a / service-b / shared, or any other split.

---

## Quick install

```
/plugin marketplace add panma-claude/marketplace
/plugin install panma-harness
```

Claude Code clones the plugin, registers its agents/commands/skills, and wires up a `UserPromptSubmit` hook that injects the activation trigger directive on every prompt. **No project files are modified.** The plugin is fully self-contained.

After install, the harness is functional in zero-config mode: any request that matches the activation triggers will route through it, dispatching to `generic-executor` as the catch-all.

For better routing, run `/harness-init` once per project — it scans the codebase, proposes a set of domain executors (and optional finisher rules), and writes them on your confirmation. See [Level 1](#level-1-domain-executors) for the manual equivalent if you'd rather hand-write them.

To upgrade or remove later:

```
/plugin update panma-harness
/plugin remove panma-harness
```

`.harness/` (runtime state in the host project) is created by the supervisor on the first cycle. You may want to add these entries to your project's `.gitignore`:

```
.harness/state.json
.harness/STOP
.harness/cycle-*.applied
```

Or `.harness/` entirely if you treat the whole directory as local-only.

---

## How activation works

The plugin ships a `UserPromptSubmit` hook (`hooks/inject-trigger.sh`) that runs on every user prompt. The hook outputs the contents of `CLAUDE-include.md` — a short list of trigger conditions — into Claude's context. Claude reads the conditions and decides whether to activate harness mode for that prompt.

Triggers (Claude activates when **any** matches):

- 3+ independent concerns (areas, modules, domains).
- Changes that have separate verification commands (different build/test entry points).
- Work that is naturally decomposable into parallel chunks.
- An explicit `/harness-start` invocation.

The harness does **not** activate for single-file edits, one-line fixes, Q&A, or single-domain work. When in doubt, the supervisor errs on the side of NOT activating.

If you want to force activation despite small-looking work, use `/harness-start`. If you want to suppress it for a request that would otherwise activate, say "do it directly" or "no harness" in your message.

The hook never modifies your project's `CLAUDE.md` — the trigger is delivered fresh each turn from the plugin install location.

---

## The cycle at a glance

```
user request
     │
     ▼
  Designer ──── emits per-area specs + verification picks (cap 4 specs per wave)
     │
     ▼
  Executors  ──── dispatched in parallel, in_background
     │            self-verify (build/test), report back
     ▼
   Main      ──── checks in periodically while workers run
     │            (TaskOutput, TaskUpdate, TaskStop as needed)
     ▼
  Verifier   ──── 6 static cross-cutting checks (diff-only, read-only)
     │            + any dynamic checks resolved from .harness/verification-checks.yaml
     │            + any ephemeral checks the user accepted "just this cycle"
     │              via the cycle-start candidate picker
     ▼
  Rule-Applier ── review skill, security skill, optional post-finish
     │            rules, optional repo registration
     ▼
  Complete (or retry up to 5 times if any phase fails)
```

The full state machine — phases, retry budget, worker check-in heuristics, idempotency rules — lives in the body of `commands/harness-iterate.md` (internal command; not for direct user use).

---

## Slash commands

| Command | Purpose |
|---------|---------|
| `/harness-init` | Scan the project, propose a set of domain executors (and optional finisher / `.gitignore` entries), then write them on your confirmation. Idempotent — safe to re-run after structural changes. |
| `/harness-start <request>` | Force-activate the harness for `<request>`, skipping trigger evaluation. |
| `/harness-status` | Print a compact snapshot of the current cycle from `.harness/state.json`. |
| `/harness-stop` | Hard-stop the cycle. Touches `.harness/STOP`, sends `TaskStop` to active workers, marks the cycle `needs_user`. |
| `/harness-reset` | Zero the retry counter without changing the request. Useful after raising the retry budget mid-cycle. |
| `/harness-iterate` | Internal — fired by `/loop` dynamic mode at each iteration. Not for direct user use. |

---

## Level 1: domain executors

The most common customization. Default behavior routes every Designer chunk to `generic-executor`, which works but is, well, generic. A domain-specific executor lets Designer route the right chunk to a worker that already knows your stack's build command, conventions, and boundary rules.

### Fastest path: `/harness-init`

```
/harness-init
```

Scans the project (workspace manifests, top-level directories, formatter configs), proposes a set of domain executors with detected build commands, and writes them on your confirmation. Also offers optional `post-finish.md` rules (formatter / linter) and `.gitignore` entries. **Nothing is written until you approve.**

Re-run any time the structure changes — existing executors are preserved, new ones are added alongside.

If the project is too small or single-domain, `/harness-init` says so and stops. Use the manual recipe below if you want full control over the wording.

### Manual recipe

1. **Pick a domain name.** Short, lowercase, hyphen-separated. Whatever maps to a coherent area of your project.

2. **Create `.claude/agents/harness/<domain>-executor.md`.** The `-executor.md` suffix is required — Designer discovers executors by scanning `.claude/agents/**/*-executor.md` recursively. Putting them under the `harness/` subdir is the canonical layout (`/harness-init` does this automatically); flat-layout `.claude/agents/<domain>-executor.md` is also recognized.

3. **Fill in the template below.** Replace every `<...>` with your project's reality.

```markdown
---
name: <domain>-executor
description: Implements changes within the <domain> area. Reads spec, edits within domain boundaries, runs the domain's build/test command, reports back.
tools: Read, Edit, Write, Bash, Grep, Glob
---

You are the **<domain>** executor in the panma-harness orchestration.

## Domain

This executor owns the `<domain>` area. It touches files under:

- `<glob-or-absolute-path-1>`
- `<glob-or-absolute-path-2>`

If a Designer spec implies changes outside these paths, refuse with `status: partial` and a `notes` line.

## Build / Test

After making changes, run:

\`\`\`
<your-actual-build-or-test-command>
\`\`\`

Two-attempt cap on test fixes. On second failure → `status: failed`.

## Conventions

<Optional: domain-specific rules that the host project's CLAUDE.md doesn't already state.>

## Reporting

Use the standard executor report shape from the orchestration skill:

\`\`\`
domain:        <domain>
status:        completed | failed | partial
changes:       [<file>, ...]
build_result:  pass | fail | n/a
test_result:   pass | fail | skipped | n/a
elapsed:       <seconds>
notes:         <free-form 0-3 lines>
\`\`\`

## Guardrails

- Stay within the listed paths.
- Two build/test attempts maximum.
- Implement exactly what the Designer spec asks for; do not expand scope.
- Honor all `constraints` from the spec.
```

4. **Save.** Designer picks it up on the next cycle — no restart needed.

### How Designer routes to it

Designer reads each `*-executor.md` file's `description` field and matches it to the chunks it decomposes the user request into. As long as your description plausibly covers what a chunk is about, that chunk gets routed to your executor. Chunks with no plausible match fall through to `generic-executor`.

### Tips

- **Keep `tools` minimal** for safety. A read-only verifier or a doc-only executor probably doesn't need `Edit, Write, Bash`.
- **Keep `description` factual**. Designer matches on real responsibilities, not aspirations.
- **Path boundaries matter.** Without them, two executors can step on each other's files within one cycle.

---

## Level 2: optional configs

### 2.1 Auto repo registration

When a cycle creates new top-level directories, rule-applier can propose registering them as new GitHub repos under your org. To enable:

```bash
cp .harness/examples/repo-registration.yaml.example .harness/repo-registration.yaml
```

Then edit the file. Every field is documented inline. Key points:

- **`default_org`** is your GitHub org or user.
- **`default_private: true`** means new repos default to private. Override per entry in `overrides`.
- **`patterns`** uses a dir glob to derive the repo name. `{name}` expands to the last segment of the matched dir.
- **`overrides`** are exact-path exceptions that win over patterns.

At cycle finalization, rule-applier reports proposals to Main, which asks you to confirm. Only on confirmation does it run `gh repo create`, init/push, and update parent `.gitignore`.

### 2.2 Post-finish rules

Project-specific finishers (formatters, linters with `--fix`, changelog updaters, free-form checks) that run after the universal `review` and `security-review` skills. To enable:

```bash
cp .harness/examples/post-finish.md.example .harness/post-finish.md
```

Each rule has a `kind`:

- **`shell`** runs a command. Deterministic fixers (formatter, `eslint --fix`, etc.) apply directly. If the command would touch many files, rule-applier proposes before applying.
- **`check`** is a free-form description. Rule-applier reads the diff and reports findings — never modifies code.

The `scope` field on `shell` rules limits the command's reach: `changed-files-only`, `whole-tree`, or a glob like `"src/**"`.

### 2.3 Skip rules

A JSON array of rule names to skip silently. Default rules are `review` and `security-review`; custom rules are whatever you named them in `post-finish.md`.

```bash
echo '["review", "security-review"]' > .harness/skip-rules.json
```

No example file needed — the format is the one line above.

### 2.4 Verification checks library

Static cross-cutting checks (the six categories in `agents/verifier.md`) catch a lot, but they can't tell you whether the running system actually answers correctly after multiple domains changed. For that, define a **library of cross-cutting checks** that the Designer picks from per cycle.

A "check" is just a shell command — `curl + bash`, a `psql -c "..."`, a custom CLI, a Postman/Newman run, a `./gradlew integrationTest`, a `pnpm playwright`, anything that exits 0 on success and nonzero on failure. You do **not** need a specific testing framework.

```bash
cp .harness/examples/verification-checks.yaml.example .harness/verification-checks.yaml
```

Each entry has:

- **`id`** — referenced by Designer's `verification` output.
- **`cmd`** — the shell command Verifier runs.
- **`timeout`** — seconds; the command is killed and reported `timeout` past this.
- **`applicable_when`** — when Designer should include this check:
  - **`user_hint: [...]`** — keywords to look for in the user request (case-insensitive). Lets you force heavy checks by saying "run playwright" in your request.
  - **`changed: [...]`** — globs to match against executor outputs. The check runs when a relevant area was touched.
  - Missing/empty `applicable_when` → always included.

The library starts empty after `/harness-init` — populating it is what the candidate picker (next subsection) is for.

#### Per-cycle candidate picker (since v0.0.18)

Init-time stack guessing creates silent-failure modes: a placeholder `cmd: <your-...>` left unfilled means dynamic verification is permanently off, and nothing reminds you. Instead, the harness asks **every cycle** what to verify, based on the actual changes about to land.

Each cycle:

1. **Designer** plans executors AND inspects their planned outputs. From that, it emits two lists:
   - `verification: [...]` — IDs already in your `verification-checks.yaml` whose `applicable_when` matches this cycle's changes (silent auto-include, current behavior).
   - `verification_candidates: [...]` — *new* checks Designer thinks would be useful here, derived from change patterns (a `pom.xml` near changed `.java` files → `mvn compile`; a changed `@Configuration` class → "startup smoke" fill_needed candidate; a changed `docker-compose.yml` → `docker compose config`).
2. **Main** presents the candidates with a 3-way picker per candidate:
   - **이번만 실행** — run as one-shot for this cycle only. Not persisted.
   - **yaml 영구 등록** — append to `verification-checks.yaml` AND run this cycle. Future cycles auto-pick when the glob matches.
   - **skip** — neither runs nor persists.
3. **Verifier** runs both the yaml-resolved spec entries and the inline ephemeral ones; reports them as `source: library` vs `source: ephemeral`.
4. **Rule-Applier** at cycle end, if any ephemeral check passed, surfaces it as a promotion candidate ("this one worked, consider 영구 등록 next time").

The picker runs regardless of `mode:` in preferences.yaml. Verification is too consequential to bypass on auto mode.

For candidates whose `cmd` is project-specific (Designer can name the *category* but can't derive a working cmd — e.g., "how do you start your service?"), the candidate ships as a `<FILL: ...>` placeholder. Verifier skips placeholder cmds at runtime rather than failing; the skip is the signal that you need to fill it in. See `examples/verification-cmd-cookbook.md` for stack-specific cmd patterns when filling these in.

#### Choosing what goes in the library

- Smoke tests, contract tests, schema validators → light, fast, almost always relevant. Use `changed:` globs and let Designer include them when the relevant area is touched.
- Full e2e suites, deploy smokes, heavy integration runs → expensive. Gate them behind `user_hint:` so they only fire when explicitly requested.
- Domain-owned tests (`pnpm --filter @app/api test`) do **not** belong here. Those are the executor's job; running them again wastes cycles.

### 2.5 Activation mode (interactive vs auto)

By default the harness activates silently — once Main decides the request matches the triggers, it just starts the cycle. For projects where you want more oversight, or where automated verification is weak (no playwright / e2e framework), drop in a preferences file:

```bash
cp .harness/examples/preferences.yaml.example .harness/preferences.yaml
```

Three modes:

| Mode | When activating | When choosing verification |
|---|---|---|
| `auto` (default) | Silent. Just runs. | Designer auto-picks library matches. **Candidate picker** runs at cycle start (see §2.4). |
| `confirm` | Shows triage decision: "I think this is harness work because <reason>. Proceed?" | Same as auto: library auto + candidate picker. |
| `interactive` | Same prompt as `confirm`. | After Proceed, asks "How should I verify?" upfront with options: **Auto-pick**, **Manual** (you verify yourself), each check id, **Skip dynamic**. When set explicitly, the candidate picker is bypassed for this cycle. |

The `Manual` option is the key escape hatch for framework-less projects: cycle runs, Verifier does its 6 static checks, then the final report says "please verify these N files yourself" — no false-positive failures from missing dynamic checks. Pair it with `interactive` mode when your project's verification story is a browser tab and a manual eye, not a CI suite.

You can change mode mid-project — flip the file to `auto` once your verification-checks.yaml gets robust, or back to `interactive` when working on something delicate.

---

## Inspecting state

The harness keeps everything for the current cycle in `.harness/state.json`. Useful contents:

- `phase` — where in the cycle we are.
- `retry_count / retry_limit` — how close we are to the hard limit (default 5).
- `active_workers` / `completed_workers` — what's running and what's done.
- `designer_history` — every dispatch the Designer has produced this cycle.
- `verifier_result`, `rule_applier_result` — outputs of those phases.
- `termination_reason` — why the cycle ended, if it has.

For a compact summary, use `/harness-status` instead of reading the JSON directly.

The `.harness/STOP` file is a kill switch: if it exists at the start of any iteration, the cycle terminates immediately. `/harness-stop` creates it; `/harness-start` removes it.

---

## Troubleshooting

### "The harness didn't activate when I expected it to."

Two common causes:

1. **Trigger didn't match.** The activation conditions are conservative on purpose. If your request looks like a single-area change to the supervisor, it won't activate. Use `/harness-start <your request>` to force.

2. **Hook not firing.** The plugin's `UserPromptSubmit` hook should run on every prompt. Confirm the plugin is installed:
   ```
   /plugin list
   ```
   If `panma-harness` is not listed, run `/plugin install panma-harness`. If listed but the hook is not firing, check Claude Code's hook logs for errors from `inject-trigger.sh`.

### "The harness activated when I didn't want it to."

Add a sentence to your request like "do it directly, no harness." The supervisor checks for that kind of opt-out language before activating.

### "Skill(loop) failed to enter dynamic mode when the supervisor tried to assistant-invoke it."

This is the known fallback path. If you see Main complaining that `Skill(skill="loop", ...)` didn't behave like a user-invoked `/loop`, use `/loop /harness-iterate <request>` directly — it activates the harness through the same protocol with user-side invocation, which is guaranteed to enter dynamic mode. A Stop-hook-driven fallback is on the roadmap for a later plugin version.

### "A worker has been running for a long time."

Run `/harness-status` to see which worker and how long. Main's check-in heuristics (in the orchestration skill) usually catch genuinely stuck workers — repeated identical errors, no edits, repeated file reads, etc. — and either send `TaskUpdate` hints or `TaskStop` + escalate to Designer.

If you want to intervene yourself, `/harness-stop` halts everything cleanly. After inspecting state, `/harness-start <new framing>` to restart with a different angle.

### "The cycle exhausted its retry budget."

Default budget is 5. When exhausted, Main pauses with `phase: needs_user` and reports the full retry history. Options:

- `/harness-reset` then `/harness-start <revised request>` — start over.
- `/harness-reset` alone — same request, fresh counter (use sparingly; if 5 attempts didn't work, often the framing is wrong).
- Stash the current changes and take over manually.

### "Designer keeps escalating immediately."

Designer escalates when it cannot see a path forward. Read the `reason` field in its escalation output. Usually means either (a) the request is too vague to decompose, or (b) the executors available don't cover the requested work and `generic-executor` isn't a great fit. Either rephrase, or write a domain executor that better matches the work.

### "state.json is corrupt / partially written."

The supervisor trusts `.harness/state.json` as the single source of truth. If a crash or manual edit leaves it in an invalid state, the next iteration will fail to read it. Recovery: delete `.harness/state.json` (and `.harness/STOP` if present) and re-issue your request. The harness will start a fresh cycle. Any actual file changes already made by previous workers remain on disk; Designer will see the current working tree and plan from there.

### "How do I make this work on a different machine?"

Same as installing any other Claude Code plugin from a marketplace: on the new machine, run `/plugin marketplace add panma-claude/marketplace` once, then `/plugin install panma-harness`. If the marketplace and plugin repos are private, the machine needs git SSH access to the panma-claude org.

---

## What this plugin won't do

These are intentional non-goals. Listing them so expectations match reality:

- **Real e2e integration testing** (spinning up multiple services and testing them together). That requires project-specific infrastructure; not in scope for v0. Future versions may add an `integration-test-executor` role.

- **Self-modifying conventions.** The plugin does not change the host project's `CLAUDE.md` beyond the marker section. Convention rules stay where you put them.

- **Background work after the loop exits.** Once a cycle completes (or terminates), there is no daemon, no watcher. The next user prompt is the next conversation.

- **Cross-project orchestration.** Each install operates on one project. Coordinating work across multiple installed projects is your job.

- **Auto-bumping the retry budget.** If a cycle hits the budget, the supervisor pauses and asks you. It will not silently raise the limit.

---

## Where to look for more

After `/plugin install`, the plugin lives at `~/.claude/plugins/marketplaces/panma/plugins/panma-harness/` (path may vary by Claude Code version). The relevant files inside:

- **The orchestration protocol in full**: `commands/harness-iterate.md` (internal command body).
- **Each universal role's contract**: `agents/<role>.md` (designer, generic-executor, verifier, rule-applier).
- **The activation trigger text**: `CLAUDE-include.md`.
- **YAML schema references**: `examples/*.example` and `examples/README.md`.
- **Issues / questions**: the [panma-claude/harness](https://github.com/panma-claude/harness) repo.
