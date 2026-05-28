---
name: kanban-issues-karr-foundation-cli
description: Use when managing karr-foundation — periodic agent execution across multiple karr boards, drain loops, and auto-block logic.
---

# karr-foundation — Periodic Agent Executor for karr Boards

Single-shot daemon that monitors multiple karr boards and runs an agent command
when work is available. Designed for cron/systemd-timer invocation.

## Quick start

```bash
# Config at ~/.config/karr-foundation/config.yml
dirs:
  - /storage/raid/home/getty/dev/perl/dbio-dev/dbio
  - /storage/raid/home/getty/dev/perl/dbio-dev/dbio-postgresql
scan:
  - /storage/raid/home/getty/dev/perl/dbio-dev   # finds dirs with .karr file

# Per-repo .karr file (in each repo root)
command: claude -p "Use karr-coordinator agent, pick next task"
on_idle: skip
drain: true
max_runtime: 1800
max_attempts: 2

# Run via cron every 5 minutes
*/5 * * * * karr-foundation
```

## Config file

Default: `~/.config/karr-foundation/config.yml`

```yaml
dirs:
  - /path/to/repo1
  - /path/to/repo2

scan:
  - /path/to/parent-dir   # finds direct children with .karr file
```

## Per-repo .karr file

Place in repo root. All keys optional except `command`.

```yaml
command: claude -p "Use karr-coordinator agent, pick next task"
on_idle: skip             # 'skip' (default) | 'always-run'
drain: true               # loop until drained (default) | false for single run
max_runtime: 1800         # seconds: per-command SIGKILL + total drain budget
max_attempts: 2           # stalls on one task before auto-block (default: 2)
max_iterations: 50        # hard cap on drain iterations (default: 50)
cooldown_base: 1          # cooldown minutes at level 0 (default: 1)
cooldown_max: 64          # cooldown ceiling in minutes (default: 64)
error_patterns:           # extra case-insensitive substrings → common-error
  - my custom api error
```

## Options

```bash
karr-foundation --config PATH       # custom config file
karr-foundation --force             # run even if no board change / open tasks
karr-foundation --dry-run --verbose # preview without executing
```

## Drain loop semantics

Each iteration runs `command` once, then classifies result:

| Outcome | Meaning | Action |
|---------|---------|--------|
| **progress** | board changed | keep draining |
| **stall** | task claimed but didn't move | bump attempt counter; auto-block after `max_attempts` |
| **common-error** | bad exit, timeout, or error pattern | exponential backoff, no task penalty |
| **idle** | agent did nothing, grabbed nothing | stop |

### Auto-block

When a task is stuck after `max_attempts`, foundation marks it blocked with:
```
blocked: auto-block: no progress after N attempts (foundation)
```
Agent can override with `karr edit --block "reason"`.

### Exponential cooldown

On common-error: repo waits `cooldown_base × 2^level` minutes (capped at `cooldown_max`).
Level resets on next clean (non-error) run.

## State files (gitignored)

```
.karr.state    # board hash, per-task attempts, cooldown, last error
.karr.lock    # PID lock (prevents concurrent runs)
.karr.log     # run log
```

## Environment

`KARR_REPO` is set to the repo path during agent execution.

## Cron example

```bash
# Every 5 minutes, all repos
*/5 * * * * karr-foundation

# With verbose logging to syslog
*/5 * * * * karr-foundation --verbose 2>&1 | logger -t karr-foundation
```

## For dbio-dev repos

Each dbio-* repo needs a `.karr` file with a command that invokes claude on the
next available task. Example:

```yaml
command: claude -p "Use karr CLI to pick next task, implement it fully, hand off or close"
on_idle: skip
drain: true
max_runtime: 900
max_attempts: 2
cooldown_base: 2
cooldown_max: 32
```

To initialize karr in a dbio repo:
```bash
cd /path/to/dbio-postgresql
karr init --name dbio-postgresql
karr create "Example task" --priority high
```

Then add the `.karr` file and configure foundation to scan the parent dir.