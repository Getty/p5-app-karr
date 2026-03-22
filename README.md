# App::karr — Kanban Assignment & Responsibility Registry

A file-based kanban board CLI for multi-agent workflows. Tasks are coordinated via Git refs — multiple AI agents can pick, claim, and hand off work across machines using `git push/fetch`.

## Installation

### Perl (local)

```bash
cpanm App::karr
```

### Docker

```bash
# Pull from Docker Hub
docker run --rm -it -w /work -v "$(pwd):/work" raudssus/karr --help

# Explicit dynamic-runtime tag
docker run --rm -it -w /work -v "$(pwd):/work" raudssus/karr:latest --help

# Fixed non-root image (UID/GID 1000:1000)
docker run --rm -it -w /work -v "$(pwd):/work" raudssus/karr:user --help
```

`raudssus/karr:latest` starts as root only long enough to inspect `/work`, then
drops to the owner of the mounted project directory before running `karr`. That
keeps task files and Git side effects owned by the host user in the common
vendor-style workflow.

`raudssus/karr:user` is the no-magic image. It is built with a fixed `karr`
user at `1000:1000` by default, and is the better base if you want to derive
your own UID-specific image in CI or a downstream repo.

**Recommended alias for the dynamic `latest` image:**

```bash
alias karr='docker run --rm -it -w /work -e HOME=/home/karr -v "$(pwd):/work" -v "$HOME/.gitconfig:/home/karr/.gitconfig:ro" -v "$HOME/.codex:/home/karr/.codex" raudssus/karr:latest'
```

Now use `karr` as if it were installed locally:

```bash
karr init --name "My Project"
karr create "Fix login bug" --priority high
karr list
```

The `-v "$(pwd):/work"` mount makes the board visible in the container, and the
`HOME=/home/karr` mount pattern keeps Git config and agent skills accessible
after the image drops privileges.

If you prefer the fixed `user` image, the equivalent alias is:

```bash
alias karr='docker run --rm -it -w /work -e HOME=/home/karr -v "$(pwd):/work" -v "$HOME/.gitconfig:/home/karr/.gitconfig:ro" -v "$HOME/.codex:/home/karr/.codex" raudssus/karr:user'
```

To build a custom fixed-user derivative, override the build args on the
`runtime-user` target:

```bash
docker build --target runtime-user \
  --build-arg KARR_UID=1010 \
  --build-arg KARR_GID=1010 \
  -t raudssus/karr:user1010 .
```

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

## Git Sync (core feature)

Board state lives in `refs/karr/*` — not in branches or commits. Every write command automatically syncs:

```
fetch refs → materialize to local files → apply change → serialize to refs → push
```

Multiple agents on different machines see each other's changes via `git push/fetch`. No merge conflicts — each task has its own ref, and locks prevent simultaneous edits.

```bash
karr sync              # full sync (pull + push)
karr sync --pull       # pull only
karr sync --push       # push only
```

## Multi-agent workflow

```bash
# Agent picks highest-priority unclaimed task
NAME=$(karr agentname)
karr pick --claim $NAME --status todo --move in-progress --json

# Agent works on the task...

# Hand off for review
karr handoff 1 --claim $NAME --note "Implementation complete" --timestamp

# Check what I'm working on
karr list --claimed-by $NAME --status in-progress

# View activity log
karr log --agent $NAME
```

## Features

- **Git-native sync** — board state in `refs/karr/*`, syncs via `git push/fetch`
- **Atomic pick with locking** — `pick` uses git ref locks to prevent race conditions
- **Activity log** — every mutation recorded, per-agent, queryable via `karr log`
- **Batch operations** — `karr move 1,2,3 done`, `karr archive 4,5,6`
- **JSON output** — `--json` on all commands for machine consumption
- **Compact output** — `--compact` for agent-friendly one-liners
- **Claim management** — claim timeouts, `--claimed-by` filter, require_claim enforcement
- **Class of service** — expedite, fixed-date, standard, intangible priority ordering
- **WIP limits** — per-status limits shown on board
- **Agent skill bundle** — ships via File::ShareDir, installable via `karr skill install`
- **Docker-first** — `latest` auto-matches `/work` ownership, `user` stays fixed at build-time UID/GID

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
