# panma-harness

Multi-agent supervisor harness for [Claude Code](https://docs.claude.com/en/docs/claude-code/overview).

Wraps Claude Code with a role-based subagent architecture:

- **Main** (supervisor) — Claude Code itself, with Ralph loop self-continuation
- **Designer** — turns user requests into per-worker specs
- **Executors** — domain workers, named and shaped by the host project (a fallback `generic-executor` is always available)
- **Verifier** — cross-cutting consistency check (read-only, no build)
- **Rule-Applier** — finalization (review skill, security review, optional repo registration)

Stack-agnostic by design. Domain executors are defined inside each host project; this plugin only ships the universal roles plus copy-paste schema templates.

## Install

This plugin is distributed via the panma Claude Code marketplace.

```
/plugin marketplace add panma-claude/marketplace
/plugin install panma-harness
```

That's it. Claude Code clones the plugin, registers its agents/commands/skills, and wires up the UserPromptSubmit hook that injects the activation trigger on every prompt. No project files modified; no `CLAUDE.md` edit; no shell script to run.

## Update / remove

```
/plugin update panma-harness
/plugin remove panma-harness
```

## Layout

```
.
├── .claude-plugin/plugin.json            # plugin manifest
├── agents/                                # universal subagents (designer, generic-executor, verifier, rule-applier)
├── commands/                              # /harness-start, /harness-status, /harness-stop, /harness-reset
│                                           # plus /harness-iterate (internal — body carries the full supervisor protocol)
├── hooks/hooks.json                       # UserPromptSubmit trigger injection
├── hooks/inject-trigger.sh                # outputs CLAUDE-include.md content
├── CLAUDE-include.md                      # trigger conditions (read by the hook, never edited into project CLAUDE.md)
├── examples/                              # placeholder templates for project-defined extensions
└── GUIDE.md                               # user-facing documentation
```

See `GUIDE.md` for the full usage guide.
