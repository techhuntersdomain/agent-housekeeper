---
name: agent-housekeeper
description: Keep a Mac that runs AI coding agents (Claude Code, Codex, Gemini CLI, opencode, Orca automations, cron jobs) from running out of memory. Use when the user says their Mac or Claude is using too much memory, is slow, or swapping; when setting up scheduled or long-running agents that must stay up for days or weeks; when asked to install, check, or tune the memory watchdog; or when asked how agents should end their runs. Installs a free, no-AI watchdog that logs memory every 10 minutes, alerts early, and can close finished automation runs.
---

# Agent Housekeeper

Two parts:
- **`scripts/housekeeper.sh`**, a plain shell script (no AI, no network, costs nothing) that macOS runs every 10 minutes. It logs what each app uses, sends a notification when memory gets tight, and, only if turned on, closes finished automation runs and helpers left behind by agents that already quit.
- **`references/building-long-running-agents.md`**, the rules for building agents that end cleanly, plus a plain-English glossary. Read it when you're setting up or reviewing scheduled agents, and hand it to any agent that builds them.

Speak to the user in plain English. Define a technical word the first time you use it.

## Install

```bash
bash <this skill folder>/scripts/install.sh
```

It copies the script to `~/.agent-housekeeper/`, creates `~/.agent-housekeeper/config.env` from `config.example.env`, and schedules it with launchd (the Mac's built-in scheduler). To remove it, run `install.sh uninstall`. Logs and settings are kept.

## Look at the machine

```bash
~/.agent-housekeeper/bin/housekeeper.sh status   # what is using memory, agent sessions, recent actions
~/.agent-housekeeper/bin/housekeeper.sh check    # same, plus what a scheduled run WOULD close; changes nothing
```

The memory history is `~/.agent-housekeeper/memory-log.csv`, one line every 10 minutes with the
biggest apps in MB. When the user says "it got slow" or "it was using 30 GB", read that file first
and find which app grew and when. Don't guess. Closed sessions are listed in `~/.agent-housekeeper/actions.log`.

Each agent session gets one of these labels:
- **automation run**: started with a written task (5+ plain words on its command line). This is the only kind that can ever be closed.
- **interactive**: started without a written task (flags only), usually someone typing into it. Never closed. A session you start yourself WITH a task on the command line counts as an automation run, so protect it with `PROTECT_PATTERN` if needed.
- **app-managed**: lives inside an app listed in `MANAGED_BY_APP` (default: the Claude desktop app). Never closed. The app's own auto-archive setting handles these.
- **service**: a server or daemon (`serve`, `server`, `daemon`). Never closed.

## Turning on cleanup

Both cleanups are **off by default**. Turn one on only after the user agrees, and explain it in one line first:

- `CLOSE_IDLE_AUTOMATION=1` closes an automation run once it has done no real work for `IDLE_MINUTES` (default 120) and is older than `MIN_AGE_MINUTES`. It sends a normal quit signal (SIGTERM, never a force-kill). Claude Code keeps the conversation, and `claude --resume` reopens it.
- `CLOSE_ORPHANS=1` closes MCP servers or headless browsers whose agent already quit and that have been running for over an hour.

Always run `check` after changing settings and show the user what would be closed. To protect
something forever, add it to `PROTECT_PATTERN` (a grep -E pattern matched against the command line).

## What the script can't do

Be honest about these limits:
- It can't archive chats or close tabs inside a desktop app. For the Claude app, set **Settings → Claude Code → Archive inactive sessions** to a few days and quit the app (Cmd+Q) when not chatting. It's not proven that archiving alone frees the app's memory. Quitting does.
- It can't stop an app from growing. It can only show you which one grew and warn you before memory runs out.
- macOS only.

## Fixing the real cause

The watchdog is a safety net. The real fix is that **every run ends when its job is done**: use
headless mode (`claude -p`, `codex exec`), reuse one session per job, or let the watchdog close
finished runs. Walk the user through `references/building-long-running-agents.md` when they set up
new scheduled agents.
