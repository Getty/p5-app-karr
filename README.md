# App::karr — Kanban Assignment & Responsibility Registry

A file-based kanban board CLI for multi-agent workflows. Perl reimplementation of [kanban-md](https://github.com/antopolskiy/kanban-md) with full interoperability.

## Installation

### Perl (local)

```bash
cpanm App::karr
```

### Docker

```bash
# Pull from Docker Hub
docker run --rm -it -v $(pwd):/work raudssus/karr --help

# Or use the latest tag
docker run --rm -it -v $(pwd):/work raudssus/karr:latest --help
```

**Recommended: Add an alias to your shell:**

```bash
alias karr='docker run --rm -it -v $(pwd):/work raudssus/karr'
```

Now use `karr` as if it were installed locally:

```bash
karr init --name "My Project"
karr create "Fix login bug" --priority high
karr list
```

The `-v $(pwd):/work` mount ensures your `karr/` board directory is accessible inside the container.

## Quick start

```bash
karr init --name "My Project"       # create board
karr create "Fix login bug" --priority high
karr list
karr board
```

## Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize a new board |
| `create` | Create a new task |
| `list` | List tasks with filtering and sorting |
| `show` | Show full task details |
| `move` | Change task status (`--next`, `--prev`, or explicit) |
| `edit` | Modify task fields, tags, claims, blocks |
| `delete` | Delete a task |
| `archive` | Soft-delete (move to archived) |
| `board` | Show board summary by status |
| `pick` | Atomically find and claim next available task |
| `handoff` | Hand off task to review with notes |
| `config` | View/modify board configuration |
| `context` | Generate markdown summary for agent embedding |
| `sync` | Sync board with remote (Git refs/karr/*) |
| `log` | Show activity log (filtered by agent/task) |
| `skill` | Install/check/update Claude Code skills |
| `agentname` | Generate random two-word agent name |

## Multi-agent workflow

```bash
NAME=$(karr agentname)
karr pick --claim $NAME --status todo --move in-progress
# ... work ...
karr handoff 1 --claim $NAME --note "Done" --timestamp
```

## Features

- **Batch operations** — `karr move 1,2,3 done`, `karr archive 4,5,6`
- **JSON output** — `--json` on all commands for machine consumption
- **Compact output** — `--compact` for agent-friendly one-liners
- **Claim management** — claim timeouts, require_claim enforcement
- **Class of service** — expedite, fixed-date, standard, intangible priority ordering
- **WIP limits** — per-status limits shown on board
- **File::ShareDir** — ships Claude Code skill, installable via `karr init --claude-skill` or `karr skill install`

## Task file format

Tasks are Markdown files with YAML frontmatter in `karr/tasks/`:

```markdown
---
id: 1
title: Fix login bug
status: in-progress
priority: high
class: standard
claimed_by: agent-1
created: 2026-03-12T10:00:00Z
updated: 2026-03-12T10:00:00Z
---

Task description here.
```

## License

This is free software; you can redistribute it and/or modify it under the same terms as the Perl 5 programming language system itself.
