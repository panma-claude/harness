# panma-harness

Multi-agent supervisor harness for [Claude Code](https://docs.claude.com/en/docs/claude-code/overview).

Wraps Claude Code with a role-based subagent architecture:

- **Main** (supervisor) — Claude Code itself, with Ralph loop self-continuation
- **Designer** — turns user requests into per-worker specs
- **Executors** — domain workers (project-defined, e.g. backend / frontend / db / infra)
- **Verifier** — cross-cutting consistency check (no build, read-only)
- **Rule-Applier** — finalization (review, security, repo registration)

## Status

Work in progress. Design locked in [HARNESS-DESIGN.md](https://github.com/panma-claude/panma-claude/blob/main/docs/HARNESS-DESIGN.md) (root repo). Implementation in progress per Stages 1–7.

## Install

`install.sh` will land in Stage 4. For now, this repo only contains the plugin manifest and folder skeleton.

## Layout

```
.
├── .claude-plugin/plugin.json   # plugin manifest
├── agents/                       # universal subagents (designer, generic-executor, verifier, rule-applier)
├── commands/                     # /harness-start, /harness-status, /harness-stop, /harness-reset
├── skills/                       # harness-orchestration skill (detailed protocol)
├── examples/                     # copy-paste templates for project-defined executors + .harness/ configs
├── CLAUDE-include.md             # auto-included into project CLAUDE.md by install.sh
├── install.sh / update.sh / uninstall.sh
└── GUIDE.md
```

See the design doc for rationale.
