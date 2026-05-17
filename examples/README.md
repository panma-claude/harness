# Examples

Two schema-reference templates for the YAML config files the harness reads. Both are **plugin-defined formats** — no other documentation source exists for them, so these examples double as the spec.

`install.sh` seeds them into the host project at `.harness/examples/` so they are always one `cp` away from being active.

| Example | Copy to | Activates |
|---------|---------|-----------|
| `repo-registration.yaml.example` | `.harness/repo-registration.yaml` | Auto-proposal of `gh repo create` for new directories at cycle finalization |
| `post-finish.md.example`          | `.harness/post-finish.md`          | Extra project-specific finishers (formatters, changelogs, custom checks) |

## How to use

1. Pick the template that matches what you want to enable.
2. Copy it to the path in the "Copy to" column (drop the `.example` suffix).
3. Replace every placeholder — anything wrapped in `<...>` — with project-specific text.
4. Re-read the comment header inside the copied file; every field's role is explained inline.

## Why no executor template here

A specialized executor is just a markdown file with YAML frontmatter and a body that explains the role. There is no plugin-defined schema beyond what Claude Code already requires for any subagent (`name`, `description`, optional `tools`). See `GUIDE.md` for a full executor recipe with inline samples.

## Why no skip-rules example here

`.harness/skip-rules.json` is a JSON array of rule names. Its full schema is one line:

```json
["<rule-name>", "<rule-name>", ...]
```

See `GUIDE.md` for which rule names exist by default and how custom rules in `post-finish.md` can be referenced.
