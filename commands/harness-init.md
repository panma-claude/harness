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

## 3b. Detect repo-registration candidacy

Propose `.harness/repo-registration.yaml` if **any of (a), (b), (c)** holds, AND the universal gates pass.

**Universal gates** (must all hold for any pattern):
- `gh` CLI on PATH (`command -v gh`).
- `.harness/repo-registration.yaml` does **not** already exist.

**Pattern (a) — workspace monorepo:**
- A workspace manifest detected in step 1 (pnpm-workspace.yaml, turbo.json, nx.json, lerna.json, Cargo workspace, go.work, parent pom.xml, parent settings.gradle*).
- At least one of `apps/`, `services/`, `packages/`, `crates/` contains 2+ subdirectories.

**Pattern (b) — polyrepo / nested-clones umbrella:**
- `find . -mindepth 2 -maxdepth 3 -name .git -type d` returns 2+ results.
- This is the "super-repo with N nested git clones" pattern (panma-claude itself, or any project where each top-level subdir is a separate git repo cloned into one workspace).

**Pattern (c) — git submodules:**
- `.gitmodules` exists at the project root with 2+ `[submodule ...]` sections.

### Generating the template

For pattern (a):
- `patterns` mirror the workspace dirs (`apps/*`, `packages/*`, etc.).
- `default_org` cannot be auto-detected → leave as placeholder.

For pattern (b):
- `patterns` mirror the **top-level dirs that contain nested clones**. E.g., if nested .gits are found under `backend/*` and `frontend/*`, emit patterns for both. Group by parent dir; do not list every leaf.
- **Auto-extract `default_org`** from one of the nested clones' git remote:
  ```
  git -C <nested-clone-path> remote get-url origin
  ```
  Parse the org from URLs like `git@github.com:<org>/<repo>.git` or `https://github.com/<org>/<repo>.git`. If multiple nested clones share the same org, use it as `default_org`. If they differ, leave placeholder and note the conflict in "Skipped checks".

For pattern (c):
- `patterns` mirror each submodule's path (or group them by parent if there are many under one dir).
- Auto-extract `default_org` from `.gitmodules` `url` entries the same way.

### When no pattern matches

Do **not** propose it. Record the reason and surface it under "Skipped checks" in step 4. The user should always be able to tell what was evaluated and why it was not proposed.

## 3c. Detect auto-commit candidacy (polyrepo only)

If pattern (b) above (polyrepo / nested-clones) is detected, additionally offer a `nested-repo-commit` post-finish rule. This rule, when added, runs after every harness cycle and creates one commit per nested repo that has changes — using the cycle's `user_request` as the commit message (via `${CLAUDE_PLUGIN_ROOT}/hooks/commit-nested.sh`).

Why this is useful: on umbrella projects, a single harness cycle often touches files spread across many nested repos. Without this rule, the user has to walk each repo and commit separately. With it, the cycle ends with N commits ready to push.

Propose only when:
- Pattern (b) matched.
- The rule is **not** already present in `.harness/post-finish.md`.

This is opt-in. Surface it as its own checkbox in the step 4 approval question (see below). Do not enable it silently.

## 3d. Skip-rules.json (intentionally not proposed)

`/harness-init` never proposes a `skip-rules.json`. It's a runtime toggle for "temporarily disable a rule," not a setup decision. Surface this in "Skipped checks" so the user knows it was considered.

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

Proposed repo-registration.yaml:
  pattern detected: polyrepo / nested-clones (21 nested .git dirs under backend/*, frontend/*)
  default_org:      panma-web        ← auto-extracted from existing nested clones
  default_private:  true
  patterns:
    - backend/*   → "{name}"
    - frontend/*  → "{name}"

Optional: auto-commit to nested repos (polyrepo-only feature)
  Adds post-finish rule: nested-repo-commit
    runs bash "${CLAUDE_PLUGIN_ROOT}/hooks/commit-nested.sh" after every cycle
    creates one commit per nested repo that has changes
    commit message derived from the cycle's user_request

Proposed .gitignore additions:
  .harness/state.json
  .harness/STOP
  .harness/cycle-*.applied
  .harness/skip-rules.json

Skipped checks (evaluated but not proposed):
  - skip-rules.json — runtime toggle, not a setup file (create manually if needed)
  - post-finish: black/ruff — no Python config detected

No changes have been written yet.
```

Then ask the user with **one `AskUserQuestion` call, `multiSelect: true`**. Each proposed section is an independent checkbox. The user picks any combination (or nothing).

Options to include (omit any section that has nothing to propose):

- `Domain executors (N proposed)` — write all proposed `*-executor.md` files (existing ones are preserved either way)
- `post-finish.md rules (N proposed)` — formatter / linter / check entries
- `repo-registration.yaml` — only if section 3b matched
- `Auto-commit to nested repos` — only if section 3c matched (polyrepo). Adds the `nested-repo-commit` rule to `post-finish.md` (creating the file if absent)
- `.gitignore additions` — runtime state ignores

After the user responds, anything left unchecked is **not written**. A response with zero checkboxes selected = full cancel.

For finer per-item control (e.g. dropping one executor while keeping the others), the user follows up with a free-form message before you proceed — do not assume their selection is final without confirmation if their checked set is partial.

## 5. Apply (only after explicit confirmation)

For each approved executor:

- Write `.claude/agents/<name>-executor.md` using the template below.
- Fill `<paths>`, `<build-command>`, and any `<conventions>` lines from the detected info. If a field has no good default, leave it as `<...>` placeholder text so the user can edit later.

For each approved finisher rule:

- Create `.harness/post-finish.md` (or append to existing) with the YAML entries.

For the approved repo-registration template (if any):

- Write `.harness/repo-registration.yaml` only if the file does **not** exist. Never overwrite.
- Pre-fill `default_org` if you successfully auto-extracted it from existing nested remotes or `.gitmodules`; otherwise leave the placeholder for the user to fill in.
- In the final report, note whether org was auto-filled ("ready to use") or left as placeholder ("edit before next cycle").

For approved auto-commit rule (polyrepo only):

- Append (or create) `.harness/post-finish.md` with a single rule:
  ```yaml
  - name: nested-repo-commit
    kind: shell
    cmd: bash "${CLAUDE_PLUGIN_ROOT}/hooks/commit-nested.sh"
    scope: whole-tree
  ```
- Do not duplicate if a `nested-repo-commit` rule already exists in the file.

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
- For `.harness/post-finish.md`: if the file exists, **append** new rules under a `# added by /harness-init` comment; never replace. For the `nested-repo-commit` rule specifically, also check by `name:` to avoid duplicates across re-runs.
- For `.harness/repo-registration.yaml`: skip silently if the file exists. Never overwrite.
- For `.gitignore`: only add lines that are not already present.

## Guardrails

- Read-only until step 5. The user must see the plan and approve.
- Do not invoke other slash commands or skills.
- Do not start a harness cycle. `/harness-init` is setup, not execution.
- Do not propose changes to `CLAUDE.md` — convention rules belong to the user.
- If you cannot detect any domains worth splitting, say so and exit. Don't force-generate.
