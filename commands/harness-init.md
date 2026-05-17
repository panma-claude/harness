---
description: Scan the project, propose a set of domain executors (and optional finisher/skip configs), then generate them on user confirmation. Idempotent — safe to re-run.
---

The user wants to bootstrap (or refresh) the project's harness customization layer. Walk the protocol below from top to bottom in a single turn. **Never modify files before the user confirms.**

## 0. Pre-flight

- If `.claude/agents/` does not exist, plan to create it. Don't create yet.
- If `.harness/` does not exist, plan to create it. Don't create yet.
- Read `CLAUDE.md` (project root) if present — domain hints there override your own guesses.

## 1. Scan the project

Goal: identify natural **domain boundaries** and the **build/test command** for each.

Read whichever of these exist at the project root (do not read recursively — top-level only at this stage):

- Workspace / monorepo manifests: `package.json`, `pnpm-workspace.yaml`, `lerna.json`, `nx.json`, `turbo.json`, `go.work`, `Cargo.toml` (workspace), `settings.gradle*`, `pom.xml` (parent)
- Single-project manifests: `pyproject.toml`, `setup.py`, `Cargo.toml` (crate), `go.mod`, `build.gradle*`, `Gemfile`, `composer.json`, `mix.exs`
- Convention dirs: `apps/`, `packages/`, `services/`, `crates/`, `cmd/`, `internal/`, `src/`, `frontend/`, `backend/`, `web/`, `api/`, `mobile/`, `migrations/`, `db/`, `infra/`, `terraform/`, `docs/`

For monorepos, also peek one level deep into the workspace dirs (e.g. `apps/*/package.json`) — that's where per-package build commands live.

**Heuristic for "domain":** a coherent area with its own build/test command, its own conventions, and clear file boundaries. Examples of good cuts:

- `backend` (`apps/api/`) + `frontend` (`apps/web/`) + `shared` (`packages/shared/`) → 3 executors
- `service-a` + `service-b` + `infra` → 3 executors
- Single-app project with `src/` + `migrations/` + `e2e/` → 3 executors

**Anti-patterns to avoid:**

- Per-file executors. If two "domains" share a build command, merge them.
- More than 5 executors total. Designer's wave cap is 4; beyond 5 the picture is too fragmented.
- Generic "all-purpose" executor — that's what `generic-executor` is already.

If the project looks too small to benefit (single file, no real domain split), say so plainly and stop — don't force executors onto a project that doesn't need them.

## 2. Detect existing executors

List `.claude/agents/*-executor.md`. For each, read the `description` field. These are **not** candidates for re-generation — preserve them. New executors must not clash on name or path coverage.

## 3. Detect formatters / linters (optional finisher candidates)

Look for these signals — each suggests a `post-finish.md` entry:

| Signal | Suggested rule |
|---|---|
| `.prettierrc*` or `prettier` in deps | `shell: prettier --write`, scope `changed-files-only` |
| `.eslintrc*` or `eslint` in deps | `shell: eslint --fix`, scope `changed-files-only` |
| `pyproject.toml` with `[tool.black]` or `[tool.ruff]` | `shell: ruff format` / `black .` |
| `rustfmt.toml` or `Cargo.toml` | `shell: cargo fmt` |
| `.golangci.yml` or `gofumpt` | `shell: gofmt -w` / `golangci-lint run --fix` |
| `.editorconfig` only | nothing — too generic |

Don't propose finishers for tools you can't see installed. If `package.json` has no `prettier` in `devDependencies`, do not propose `prettier --write` — but if the signal table above is something you actively checked for and rejected, record it for the "Skipped checks" section in step 4 so the user sees what was evaluated.

## 3b. Detect repo-registration candidacy (optional, niche)

Only propose `.harness/repo-registration.yaml` if **all** of these hold:

- The project is a monorepo (workspace manifest detected in step 1).
- At least one of `apps/`, `services/`, `packages/`, `crates/` contains 2+ subdirectories that each look like an independent unit (own manifest file, own README, etc.).
- `gh` CLI is available on PATH (check with `command -v gh`).
- `.harness/repo-registration.yaml` does **not** already exist.

If candidacy holds, propose a **template** — you cannot auto-detect the org name or naming convention, so leave those as placeholders the user must fill in. Mark this clearly in the plan output:

```
repo-registration.yaml — TEMPLATE (you must fill in placeholders before it activates)
  default_org:    <your-github-org-or-user>
  default_private: true
  patterns:
    - dir: "apps/*"      → repo_name: "{name}"
    - dir: "packages/*"  → repo_name: "{name}"
```

If candidacy does **not** hold, do **not** propose it — but record the reason and surface it in the final plan under "Skipped checks" (see step 4). The user should always be able to tell what was evaluated and why it was not proposed.

## 4. Present the plan to the user

Output a single, scannable block. Do **not** call any tools beyond Read/Glob/Bash for inspection at this point.

The plan **must** include a "Skipped checks" section at the end listing every optional component you evaluated but chose not to propose, with a one-line reason. This makes the command's decisions auditable — the user should never wonder "did it consider X?". If nothing was skipped, write `Skipped checks: none`.

Format:

```
Detected stack: <one-line summary, e.g. "pnpm monorepo, 3 workspaces, TypeScript">

Proposed domain executors (N):

  1. backend-executor
       paths:  apps/api/src/**, apps/api/test/**
       build:  pnpm --filter @app/api build && pnpm --filter @app/api test
       reason: detected NestJS app at apps/api with its own scripts.test

  2. frontend-executor
       paths:  apps/web/src/**, apps/web/test/**
       build:  pnpm --filter @app/web build && pnpm --filter @app/web test
       reason: detected Next.js app at apps/web

  3. db-executor
       paths:  packages/db/prisma/**, packages/db/migrations/**
       build:  pnpm --filter @app/db prisma:validate
       reason: detected Prisma schema with separate validate script

Existing executors (kept as-is):
  - shared-executor (will not overwrite)

Proposed post-finish.md rules (N):
  1. format       — shell: pnpm prettier --write, scope: changed-files-only
  2. eslint-fix   — shell: pnpm eslint --fix, scope: changed-files-only

Proposed repo-registration.yaml (TEMPLATE — fill in before it activates):
  default_org:      <your-github-org-or-user>
  default_private:  true
  patterns:
    - apps/*      → "{name}"
    - packages/*  → "{name}"

Proposed .gitignore additions:
  .harness/state.json
  .harness/STOP
  .harness/cycle-*.applied

Skipped checks (evaluated but not proposed):
  - repo-registration.yaml — not a monorepo (no apps/packages/services/crates dirs found)
  - post-finish: black/ruff — no Python config detected

No changes have been written yet.
```

Then ask the user one of:

- **Approve all** — write everything as shown
- **Edit** — call out which items to drop, rename, or merge
- **Cancel** — write nothing

Use `AskUserQuestion` for this. Offer at minimum: "Apply all", "Pick which to apply", "Cancel".

## 5. Apply (only after explicit confirmation)

For each approved executor:

- Write `.claude/agents/<name>-executor.md` using the template below.
- Fill `<paths>`, `<build-command>`, and any `<conventions>` lines from the detected info. If a field has no good default, leave it as `<...>` placeholder text so the user can edit later.

For each approved finisher rule:

- Create `.harness/post-finish.md` (or append to existing) with the YAML entries.

For the approved repo-registration template (if any):

- Write `.harness/repo-registration.yaml` only if the file does **not** exist. Never overwrite.
- Write the template verbatim with placeholders intact (`<your-github-org-or-user>` etc.) — the user fills them in.
- In the final report, note "repo-registration.yaml written as template — edit placeholders before next cycle."

For `.gitignore`:

- If `.gitignore` exists, append the lines under a `# panma-harness` section. Skip lines already present (verbatim match).
- If `.gitignore` does not exist, create it with just those lines.

If an `<name>-executor.md` already exists with the same name, **do not overwrite**. Report it as "kept" and continue.

## 6. Executor template

```markdown
---
name: <name>-executor
description: Implements changes within the <domain> area. Reads spec, edits within domain boundaries, runs build + tests, reports back.
tools: Read, Edit, Write, Bash, Grep, Glob
---

You are the **<domain>** executor in the panma-harness orchestration.

## Domain

This executor owns the `<domain>` area. It touches files under:

- <path-glob-1>
- <path-glob-2>

If a Designer spec implies changes outside these paths, refuse with `status: partial` and a `notes` line.

## Build / Test

After making changes, run:

\`\`\`
<build-command>
\`\`\`

Two-attempt cap on test fixes. On second failure → `status: failed`.

## Conventions

<one to three lines of detected-or-known domain conventions, or the literal "Follow the project's CLAUDE.md.">

## Reporting

Use the standard executor report shape:

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

## 7. Final report

After all writes, print one summary block:

```
harness-init complete.

Wrote:
  .claude/agents/backend-executor.md
  .claude/agents/frontend-executor.md
  .claude/agents/db-executor.md
  .harness/post-finish.md
  .gitignore  (appended)

Kept (already present):
  .claude/agents/shared-executor.md

Next steps:
  - Open the new executor files and tighten the description / paths / conventions if needed.
  - Trigger the harness on a real multi-area request, or invoke /harness-start <request>.
  - Re-run /harness-init any time the project structure changes; existing executors are preserved.
```

If the user canceled at step 4, just say `harness-init canceled. No files were written.` and stop.

## Idempotency rules

- Re-running `/harness-init` must be safe.
- Never overwrite an existing `<name>-executor.md`. Show it as "kept".
- For `.harness/post-finish.md`: if the file exists, **append** new rules under a `# added by /harness-init` comment; never replace.
- For `.harness/repo-registration.yaml`: skip silently if the file exists. Never overwrite.
- For `.gitignore`: only add lines that are not already present.

## Guardrails

- Read-only until step 5. The user must see the plan and approve.
- Do not invoke other slash commands or skills.
- Do not start a harness cycle. `/harness-init` is setup, not execution.
- Do not propose changes to `CLAUDE.md` — convention rules belong to the user.
- If you cannot detect any domains worth splitting, say so and exit. Don't force-generate.
