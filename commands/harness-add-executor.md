---
description: Add one new domain executor (+ matching cross-cutting verification entry) without re-running the full /harness-init scan.
---

The user wants to add a single domain executor mid-project. This is the targeted variant of `/harness-init` for one-off additions. Walk the protocol below in a single turn. **Never modify files before the user confirms.**

## 0. Pre-flight — parse `$ARGUMENTS`

Supported tokens:

| Token | Meaning |
|---|---|
| `<name>` (positional, required) | kebab-case domain name; final file becomes `<name>-executor.md` |
| `--paths "<glob>[,<glob>]..."` | comma-separated path globs the executor owns |
| `--build "<command>"` | build/test command for self-verify |
| `--convention "<text>"` | one-line convention reminder (default: `Follow the project's CLAUDE.md.`) |
| `--no-verification` | skip the verification-checks.yaml append |

Rules:

- If `<name>` is missing → abort with `Usage: /harness-add-executor <name> [--paths ...] [--build ...] [--convention ...] [--no-verification]`.
- If `<name>` is not kebab-case (lowercase + digits + `-`, starts with a letter) → abort with the same usage line and a one-line reason.
- If `<name>` already ends in `-executor`, strip the suffix (so `ml-pipeline-executor` and `ml-pipeline` both produce `ml-pipeline-executor.md`).

## 1. Uniqueness check

Check both layouts (harness-init §2a recognizes both):

- `.claude/agents/harness/<name>-executor.md` (new layout, harness-managed)
- `.claude/agents/<name>-executor.md` (legacy flat layout)

If either exists → abort:

```
Executor "<name>-executor" already exists at <path>.
To replace it, edit the file directly or delete it and re-run.
```

Never overwrite.

## 2. Gather missing inputs (interactive)

If any of `paths`, `build`, `convention` were not provided as flags, fill them via **one** `AskUserQuestion` call (up to 3 sub-questions, each with a prefill option as the recommended choice).

### 2a. Scan for prefill (only when at least one flag is missing)

Read the project structure at depth ≤ 2 from the root:

- Directories matching `<name>`, `<name>-*`, or `<name>s` → candidate for `paths`. Emit two globs: `<dir>/**` plus a sibling test/spec dir if one exists (`<dir>/test/**`, `<dir>/tests/**`, `<dir>/__tests__/**`).
- Build manifest inside that directory (or at the root if no directory matched):
  - `package.json` → prefer `pnpm --filter <pkg>` if `pnpm-workspace.yaml` exists; otherwise `npm test` or the project's existing test script.
  - `pyproject.toml` → `pytest <dir>` (or `python -m pytest <dir>`).
  - `Cargo.toml` → `cargo test -p <pkg>` or `cargo test`.
  - `go.mod` → `go test ./<dir>/...`.
  - `build.gradle*` / `pom.xml` → `./gradlew test` or `mvn test`.
  - Otherwise → leave the build slot as `<fill-in>`.
- Convention prefill: if the host `CLAUDE.md` has a section mentioning `<name>` or the directory, quote one line; otherwise default to `Follow the project's CLAUDE.md.`.

Each prefill becomes the first option (recommended) in its sub-question. The user may pick "Other" to type a free-form value.

### 2b. After the answers

Treat `<...>` placeholders as "leave for the user to fill later in the file" — do not block on them. Do not prompt repeatedly.

## 3. Plan the verification entry

Unless `--no-verification` is set:

- Target file: `.harness/verification-checks.yaml`.
- New entry shape:

  ```yaml
  # --- added by /harness-add-executor <name>
  - id: <name>-cross-cutting
    description: "Cross-cutting check covering <name> alongside neighboring domains"
    cmd: <fill-in>
    timeout: 300
    applicable_when:
      - changed: [<paths-as-yaml-list>]
  ```

- The `cmd` is **always** left as `<fill-in>` (matches harness-init §3e policy — never auto-fill).
- If an entry with the same `id` already exists in the file, plan to **skip** the append (do not duplicate). Note this in the plan.
- If the file does not exist yet, plan to create it with the example header from `harness/examples/verification-checks.yaml.example` plus the new entry.

## 4. Show the plan (no writes yet)

Print one scannable block:

```
Proposed executor:
  name:         <name>-executor
  paths:        <glob>, <glob>, ...
  build:        <build-command>
  convention:   <convention-line>
  target file:  .claude/agents/harness/<name>-executor.md   (new)

Proposed verification entry:
  id:           <name>-cross-cutting
  target file:  .harness/verification-checks.yaml   (new | append)
  cmd:          <fill-in>  ← edit after writing

(or: "Verification entry skipped (--no-verification)." if the flag was set)
(or: "Verification entry "<name>-cross-cutting" already exists — will be skipped.")

No changes have been written yet.
```

Then ask via a single `AskUserQuestion`:

- `Proceed` (recommended)
- `Edit values` — user follows up with a free-form correction, then re-run the plan
- `Cancel`

On `Cancel` or anything not interpretable as proceed → print `add-executor canceled. No files were written.` and stop.

## 5. Apply (only after explicit confirmation)

### 5a. Executor file

Write `.claude/agents/harness/<name>-executor.md` using the template from `/harness-init` §6. Substitute:

- `<name>` → the name argument
- `<domain>` → the name (use as-is; users can edit to a more human label after)
- `<path-glob-1>`, `<path-glob-2>` → the paths split on comma; if only one path was given, omit the second bullet
- `<build-command>` → the build command (or leave `<fill-in>` placeholder if missing)
- conventions block → the convention line

Create `.claude/agents/harness/` if missing.

### 5b. Verification entry

If `--no-verification` was not set AND no duplicate id exists:

- File does not exist → write the example header (copy from `harness/examples/verification-checks.yaml.example`, lines 1–30 — the `checks:` opener) and append the new entry.
- File exists → append the new entry under the existing `checks:` list. Preserve existing entries verbatim. Add the `# --- added by /harness-add-executor <name>` comment line above the new entry.

If a duplicate id exists → skip silently (already warned in the plan).

## 6. Final report

Print one block:

```
Added executor: <name>-executor

Wrote:
  .claude/agents/harness/<name>-executor.md
  .harness/verification-checks.yaml  (<created | appended>)

Next steps:
  - Open the executor file and tighten the paths / build / conventions if needed.
  - Fill in the `cmd:` field of the new verification entry.
  - Trigger a real request that touches <name> to dogfood, or /harness-start to force-activate.
```

If `--no-verification` was set, omit that line and add: `Verification entry not added (--no-verification).`
If the verification append was skipped due to duplicate id, replace the verification line with: `Verification entry "<name>-cross-cutting" already present — kept as-is.`

## Idempotency rules

- Never overwrite an existing `<name>-executor.md` (either layout).
- Never overwrite an existing entry in `.harness/verification-checks.yaml` with the same `id:`. Skip silently.
- `.harness/verification-checks.yaml` is created only when missing; never replace.
- `.claude/agents/harness/` is created when missing; never destructive.

## Guardrails

- Read-only until step 5. Plan must be shown and confirmed first.
- Do not invoke other slash commands or skills.
- Do not start a harness cycle. This is setup, not execution.
- Do not modify the host project's `CLAUDE.md`.
- Do not propose `--suggest`-style multi-candidate scans — that is a future addition.
