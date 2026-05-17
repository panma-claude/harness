# panma-harness

Multi-agent supervisor harness for [Claude Code](https://docs.claude.com/en/docs/claude-code/overview).

Wraps Claude Code with a role-based subagent architecture:

- **Main** (supervisor) — Claude Code itself, with Ralph loop self-continuation
- **Designer** — turns user requests into per-worker specs
- **Executors** — domain workers, named and shaped by the host project (a fallback `generic-executor` is always available)
- **Verifier** — cross-cutting consistency check (read-only, no build)
- **Rule-Applier** — finalization (review skill, security review, optional repo registration)

Stack-agnostic by design. Domain executors are defined inside each host project; this plugin only ships the universal roles plus copy-paste templates.

## Status

Work in progress. Implementation tracked by Stage in `GUIDE.md`.

## Install

`install.sh` lands in a later stage. For now this repo only contains the plugin manifest and folder skeleton.

## Layout

```
.
├── .claude-plugin/plugin.json   # plugin manifest
├── agents/                       # universal subagents (designer, generic-executor, verifier, rule-applier)
├── commands/                     # /harness-start, /harness-status, /harness-stop, /harness-reset
├── skills/                       # harness-orchestration skill (detailed protocol)
├── examples/                     # placeholder templates for project-defined executors + .harness/ configs
├── CLAUDE-include.md             # auto-appended to project CLAUDE.md by install.sh
├── install.sh / update.sh / uninstall.sh
└── GUIDE.md
```
