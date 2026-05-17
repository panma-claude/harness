# Examples

Copy-paste templates for the per-project files the harness optionally reads. `install.sh` seeds these into the host project at `.harness/examples/` so they are always one `cp` away from being active.

| Example | Copy to | Activates |
|---------|---------|-----------|
| `your-domain-executor.md.example` | `.claude/agents/<your-domain>-executor.md` | A specialized executor that Designer can route to by name |
| `repo-registration.yaml.example`  | `.harness/repo-registration.yaml`          | Auto-proposal of `gh repo create` for new directories at cycle finalization |
| `post-finish.md.example`          | `.harness/post-finish.md`                  | Extra project-specific finishers (formatters, changelogs, custom checks) |
| `skip-rules.json.example`         | `.harness/skip-rules.json`                 | A list of rule names rule-applier should silently skip |

## How to use

1. Pick the template that matches what you want to enable.
2. Copy it to the path in the "Copy to" column (drop the `.example` suffix).
3. Replace every placeholder — anything wrapped in `<...>` or `{{...}}` — with project-specific text.
4. Re-read the surrounding file for any block comment that explains constraints.

## What goes in each placeholder

**`<your-domain>`**, **`<area-1>`**, **`<area-2>`** — a short label for an area of your project (e.g. a service name, a layer, a module group). Use the same label consistently throughout the file.

**`<absolute-or-glob-path-N>`** — actual filesystem paths the executor is allowed to read/edit. Use absolute paths or glob patterns (`/repo/src/api/**`).

**`{{BUILD_COMMAND}}`** — the literal command line to verify changes in this domain (e.g. `pytest tests/`, `npm test --prefix ui`, `./gradlew :api:test`). Run it as if from the project root.

**`<convention-rule-N>`** — short statements like "all public APIs return Result<T, E>" or "use 4-space indentation". The host project's `CLAUDE.md` already covers project-wide conventions; only add what is specific to this domain here.

**`<your-github-org-or-user>`**, **`<area-N>/*`**, **`<suffix>`**, etc. (in `repo-registration.yaml.example`) — see the comment header inside that file; every field's role is explained inline.

**`<rule-name-N>`**, **`<your-formatter-or-linter-command>`** (in `post-finish.md.example`) — see the comment header inside that file.

## Naming the executor agent

The harness Designer discovers executors by scanning `.claude/agents/*-executor.md`. To make your new executor reachable:

1. Place it at `.claude/agents/<domain>-executor.md` (the `-executor.md` suffix is required).
2. Make sure the `name:` field in the YAML frontmatter matches the filename stem.

Designer will then see this executor on its next dispatch and route matching specs to it.

## Skipping defaults

The default rule-applier behavior runs the `review` and `security-review` skills universally. If those are noisy or unwanted for a particular project, add their names to `.harness/skip-rules.json`:

```json
["review", "security-review"]
```

Any rule named in `post-finish.md` can also be skipped by name.
