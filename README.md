# agent-housekeeper

Keeps a Mac that runs AI coding agents from running out of memory.

If you run Claude Code, Codex, Gemini CLI, opencode or similar agents on a schedule (Orca automations, cron, launchd, your own scripts), finished runs tend to stay open and hold their memory. After a few days the Mac is swapping and everything is slow. This fixes that.

- **Free.** It's a plain shell script. No AI calls, no network, no accounts.
- **Safe by default.** Out of the box it only watches, logs and warns. Closing anything is opt-in, and it never touches sessions started without a written task.
- **Works with any scheduler.** Tested with Claude Code; also recognises Codex, Gemini CLI, opencode and others by name.

## What it does

Every 10 minutes it:
1. Writes a line to `~/.agent-housekeeper/memory-log.csv` with what each app (with its helpers) is using. When the Mac gets slow, you can see exactly what grew.
2. Sends a macOS notification when one app uses more than 8 GB, more than 4 GB has been pushed onto the disk (swap), or free memory drops below 15%.
3. *(Optional)* Closes **automation runs** that have finished but stayed open (idle for 2 hours).
4. *(Optional)* Closes **left-behind helpers**: MCP servers and headless browsers whose agent already quit.

## Install

```bash
git clone https://github.com/techhuntersdomain/agent-housekeeper.git ~/.claude/skills/agent-housekeeper
bash ~/.claude/skills/agent-housekeeper/scripts/install.sh
```

Putting it in `~/.claude/skills/` also makes it a Claude Code skill, so you can just ask Claude "check my memory" or "turn on cleanup for finished runs".

## Use

```bash
~/.agent-housekeeper/bin/housekeeper.sh status   # what's using memory right now
~/.agent-housekeeper/bin/housekeeper.sh check    # what it would close (changes nothing)
```

Settings are in `~/.agent-housekeeper/config.env`. To turn on cleanup:

```bash
CLOSE_IDLE_AUTOMATION=1   # close finished automation runs
CLOSE_ORPHANS=1           # close left-behind MCP servers / headless browsers
```

Uninstall: `bash scripts/install.sh uninstall`

## How it decides what's safe to close

A session is closed only if **all** of these are true:
- it was started with a written task (a task written on its command line; sessions started with flags only are never closed),
- it has done no real work for 2 hours (`IDLE_MINUTES`),
- it's not inside an app that manages its own sessions (`MANAGED_BY_APP`, default the Claude desktop app),
- it doesn't match your `PROTECT_PATTERN`.

It sends a normal quit signal, not a force-kill. Claude Code saves conversations, so `claude --resume` brings one back.

## The real fix

The watchdog is a safety net. [references/building-long-running-agents.md](references/building-long-running-agents.md) explains how to build agents whose runs end on their own, with a plain-English glossary and a brief you can paste to the agents that build your agents.

## License

MIT
