# Building agents that can run for weeks

Give this to any agent (or person) that sets up scheduled or always-on AI agents. It works the same
whether the agents are started by Orca, cron, launchd, a script, or by hand.

## The one rule

**Every run must end, and give its memory back, when its job is done.**

A run that finishes its job but stays open still holds its memory, and so do its helper programs
(MCP servers, browsers). Two runs a day that never close make 14 open sessions a week, then 60 a
month. The Mac slows down, starts using the disk as memory, and eventually you have to restart
everything. If every run ends, a machine can run agents for weeks without a restart.

## Words to use (so everyone means the same thing)

| Word | Meaning |
|---|---|
| **Agent** | An AI program that does tasks: Claude Code, Codex, Gemini CLI, and so on. |
| **Session** | One open conversation with an agent. It holds memory until it is closed. |
| **Run** | One time a scheduled job fires. A good run is one session that ends at the end. |
| **Automation / scheduled job** | Something that starts a run on a timer, for example "every day at 08:30". |
| **Interactive session** | A session that waits for a person to type after each reply. **It does not close by itself**, even when the agent says "done". |
| **Headless (print) mode** | The agent does one task and then quits by itself. For Claude Code this is `claude -p "task"`, for Codex `codex exec "task"`, for Gemini `gemini -p "task"`. This is the best choice for scheduled jobs. |
| **Reuse session** | Sending each new run into the same open session instead of opening a new one. Stops the pile-up, but the conversation keeps growing, so start it fresh now and then. |
| **Idle** | Open but doing nothing. An idle session still holds memory. |
| **Process** | One program running on the computer. Every session is a process, and its helpers are more processes. |
| **RAM / memory** | The computer's fast working space. A 16 GB Mac has 16 GB in total, for everything. |
| **Swap** | When memory is full, the Mac parks some of it on the disk. That disk space is swap. It's slow, and it's why the computer drags. |
| **MCP server** | A helper program an agent starts to get extra tools (browser, database, Figma...). Each agent starts **its own copy** of every MCP server it is set up with. |
| **Orphan / left-behind helper** | A helper process whose agent already quit but that is still running. |
| **Watchdog** | A small program on a timer that checks memory and cleans up leftovers. `agent-housekeeper` is one. |

## Checklist for every agent you build

1. **Pick the right kind of run.**
   - For a job with no person watching, use **headless mode** (`claude -p`, `codex exec`, `gemini -p`). It quits by itself.
   - If the platform only opens interactive sessions, either **reuse one session** for that job or let the **watchdog close finished runs**.
2. **Writing "stop" in the prompt is not enough.** "Report and stop" ends the agent's turn, but the session stays open. Something has to actually close it: headless mode, the platform, or the watchdog.
3. **One job per run.** Short runs that end are better than one giant session doing everything.
4. **Close what you open.** If the run opened a browser, a dev server, or a tunnel, it closes them before it finishes.
5. **Load only the MCP servers the job needs.** Five MCP servers × ten sessions = fifty helper programs.
6. **Start fresh instead of growing forever.** A session that has been chatting for days holds all of that conversation in memory. New task, new session.
7. **Cap how many agents run at once.** Measured on a 16 GB Mac: one Claude Code session with its helpers used about 0.7–0.8 GB while waiting. Busy sessions, browsers and big conversations use more. Check `housekeeper.sh status` on your own machine and leave plenty of room for your normal apps.
8. **Leave a trace.** Each run writes one or two lines about what it did. Nobody should need to keep a session open just to read what happened.
9. **Don't let agents start agents without an end.** A sub-agent or worker has to end when its piece is done, just like the run that started it.
10. **Install the watchdog** (`agent-housekeeper`) as a safety net. It logs memory every 10 minutes, alerts before things get bad, and can close finished automation runs.

## Paste-ready brief for an agent that is building agents

> When you set up a scheduled or long-running agent, make sure every run ends and releases its memory
> when its job is done. Prefer headless mode (`claude -p "<task>"`, `codex exec "<task>"`) for
> scheduled jobs. If the platform only supports interactive sessions, reuse one session per job or
> rely on the agent-housekeeper watchdog to close finished runs, and tell me which you chose. Load
> only the MCP servers the job needs. Close any browser, server, or tunnel the run opened. Keep each
> run to one job and have it write a short record of what it did. Don't run more than 3 heavy agents
> at the same time on a 16 GB machine. When you're done, tell me in plain English how each
> agent ends.

## Keeping a Mac running agents for weeks

- **Runs end, so memory gets given back.** That's the rule above, and it matters most.
- **The watchdog is on**, so leftovers get caught and you get warned early. Run `~/.agent-housekeeper/bin/housekeeper.sh status` any time to see what's using memory.
- **Close chat apps you aren't using.** Desktop chat apps (Claude, ChatGPT, etc.) get bigger the longer they stay open. Your scheduled agents don't need them open, because the scheduler starts the agent program itself. Quit the app (Cmd+Q) when you're not chatting and its memory comes back.
- **Shorten the Claude app's auto-archive setting** (Settings → Claude Code → Archive inactive sessions). Then old chats get cleared automatically.
- **A weekly restart of the scheduler app is optional insurance**, not a requirement. Do it at a quiet time, such as Sunday night.

## Notes for Orca

From watching a Mac that runs Orca, plus Orca's own help text (`orca automations create --help`):

- Seen on that Mac: each automation run opened an **interactive** Claude session in an Orca terminal, and the session stayed open after the agent finished (some for almost two days). That's the pile-up described above. Each one was small (about 0.15 GB), but they add up.
- **`--reuse-session`** sends later runs into the previous live session instead of opening a new one.
  It only works for automations that use an existing workspace (`--workspace ...`), and it **can't be
  combined with `--extra-agent-args`** (so no `--model opus` on that automation). Use it for
  frequent, small check-ins.
- **`--precheck "<command>"`** skips a run when there's nothing to do (the command must exit 0 for the run to happen). Fewer pointless runs means fewer sessions.
- **`--workspace-mode new-per-run`** creates a fresh git worktree for every run. That's a full copy of the files on disk each time, so only use it for code changes that need their own branch.
- If you can't reuse sessions (for example the brain sessions that need `--model opus`), turn on
  **`CLOSE_IDLE_AUTOMATION=1`** in the watchdog. It closes a run once it has been idle for `IDLE_MINUTES` (set it to
  1440, one day, if you read results in Orca's app or on your phone, so they stay up long enough to look at). The
  conversation is still saved by Claude Code (`claude --resume` reopens it).
- Check what happened with `orca automations runs --id <automation-id>`.
