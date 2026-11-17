#!/bin/bash
# agent-housekeeper — keeps AI coding agents from eating a Mac's memory.
#
#   housekeeper.sh run      what the scheduler runs: log, alert, and (only if turned on) close idle runs
#   housekeeper.sh check    show what it sees and what it WOULD do; changes nothing
#   housekeeper.sh status   plain-English summary plus the last few log lines and actions
#
# No AI, no network, no paid anything. macOS only (uses top, ps, sysctl, memory_pressure, osascript).
set -u

DATA="${AH_HOME:-$HOME/.agent-housekeeper}"
mkdir -p "$DATA"

# ---- defaults (override any of these in $DATA/config.env) ----
AGENT_NAMES="claude codex gemini opencode cursor-agent aider qwen goose amp crush"
APP_ALERT_GB=8            # alert when one app (with its helpers) uses more than this
SWAP_ALERT_GB=4           # alert when the Mac has pushed more than this onto the disk
FREE_ALERT_PCT=15         # alert when free memory drops below this percent
NOTIFY=1                  # 1 = show macOS notifications, 0 = log only
ALERT_REPEAT_HOURS=6      # don't repeat the same alert more often than this
CLOSE_IDLE_AUTOMATION=0   # 1 = close finished automation runs (see SKILL.md); 0 = report only
IDLE_MINUTES=120          # a run counts as finished after this long without real work
IDLE_CPU_SECONDS=10       # CPU use below this between two checks still counts as idle (a waiting agent ticks a little)
MIN_AGE_MINUTES=60        # never touch a session younger than this
PROMPT_WORDS=5            # a session started with at least this many plain words counts as an automation run
PROTECT_PATTERN=''        # sessions whose command line matches this (grep -E) are never closed
MANAGED_BY_APP="Claude"   # apps that manage their own sessions (space-separated); their sessions are never closed
ORPHAN_PATTERN='mcp|playwright|--headless|chrome-devtools'
CLOSE_ORPHANS=0           # 1 = close helper processes left behind by agents that already exited
LOG_KEEP_LINES=5000
[ -f "$DATA/config.env" ] && . "$DATA/config.env"

MODE="${1:-run}"
NOW=$(date +%s)
STAMP=$(date '+%Y-%m-%d %H:%M')
LOG="$DATA/memory-log.csv"
ACTIONS="$DATA/actions.log"
STATE="$DATA/idle.state"
ALERTS="$DATA/alerts.state"
touch "$STATE" "$ALERTS"

# ---- 1. take a snapshot of every process ----
# top's MEM column is the real footprint (includes compressed memory). ps RSS undercounts it.
TOPMEM=$(top -l 1 -stats pid,mem 2>/dev/null | awk '/^PID/{f=1;next} f && $1 ~ /^[0-9]+$/ {print $1, $2}')
PSOUT=$(ps -axo pid=,ppid=,etime=,time=,args=)

SNAP=$(awk -v agents=" $AGENT_NAMES " -v pw="$PROMPT_WORDS" -v orph="$ORPHAN_PATTERN" '
function mb(v,  u, n) { sub(/[+-]$/, "", v); u = substr(v, length(v)); n = substr(v, 1, length(v)-1) + 0
  if (u == "K") return n/1024; if (u == "M") return n; if (u == "G") return n*1024; if (u == "B") return n/1048576
  return (v+0)/1048576 }
function secs(t,  d, a, n, s, i) { d = 0; if (index(t, "-")) { split(t, a, "-"); d = a[1]; t = a[2] }
  n = split(t, a, ":"); s = 0; for (i = 1; i <= n; i++) s = s*60 + a[i]; return d*86400 + s }
function label(p,  a, s, n) { a = args[p]
  if (match(a, /\/[^\/]+\.app\//)) { s = substr(a, RSTART+1, RLENGTH-6); return s }
  split(a, s, " "); n = split(s[1], s, "/"); return s[n] }
NR == FNR { mem[$1] = mb($2); next }
{ p = $1; ppid[p] = $2; age[p] = int(secs($3)/60); cpu[p] = secs($4)
  a = $0; sub(/^[ ]*[0-9]+[ ]+[0-9]+[ ]+[^ ]+[ ]+[^ ]+[ ]+/, "", a); args[p] = a; pids[++np] = p }
END {
  for (i = 1; i <= np; i++) { p = pids[i]; q = p; hops = 0
    while (q in ppid && hops < 60) { sm[q] += mem[p]; sc[q] += cpu[p]; top = q
      if (ppid[q] <= 1 || !(ppid[q] in ppid)) break; q = ppid[q]; hops++ }
    root[p] = top }
  for (i = 1; i <= np; i++) { p = pids[i]; g[label(root[p])] += mem[p] }
  for (k in g) if (g[k] >= 50) printf "GROUP\t%d\t%s\n", g[k], k
  for (i = 1; i <= np; i++) { p = pids[i]; if (mem[p] >= 200) printf "PROC\t%d\t%s\n", mem[p], substr(label(p) " " p, 1, 40) }
  for (i = 1; i <= np; i++) { p = pids[i]; nm = label(p); n = split(args[p], t, " "); first = 2
    if (nm ~ /^(node|bun|deno)$/ && n >= 2) { k = split(t[2], b, "/"); nm = b[k]; sub(/\.(m?js|ts)$/, "", nm); first = 3 }
    if (index(agents, " " nm " ") && !(ppid[p] in args && label(ppid[p]) == nm)) {
      w = 0; skip = 0
      for (j = first; j <= n; j++) {
        if (t[j] ~ /^-/) { skip = (t[j] !~ /=/); continue }        # a flag; the next token may be its value
        if (skip) { skip = 0; continue }
        if (t[j] ~ /^[A-Za-z][A-Za-z\047,.:;!?]*$/) w++ }
      printf "AGENT\t%s\t%d\t%.2f\t%d\t%d\t%s\t%s\n", p, sm[p], sc[p], age[p], (w >= pw), label(root[p]), args[p] }
    if (ppid[p] == 1 && age[p] >= 60 && args[p] ~ orph)
      printf "ORPHAN\t%s\t%d\t%d\t%s\n", p, sm[p], age[p], args[p] }
}' <(echo "$TOPMEM") <(echo "$PSOUT"))

FREE_PCT=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{gsub(/%/,"",$2); print $2+0}')
SWAP_MB=$(sysctl -n vm.swapusage | awk '{for(i=1;i<=NF;i++) if($i=="used"){v=$(i+2); sub(/M/,"",v); print int(v)}}')
TOTAL_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
GROUPS_SORTED=$(echo "$SNAP" | awk -F'\t' '$1=="GROUP"{print $2"\t"$3}' | sort -rn)

gb() { awk -v m="$1" 'BEGIN{printf "%.1f", m/1024}'; }

notify() { # key, message
  [ "$NOTIFY" = 1 ] || return 0
  local last; last=$(awk -v k="$1" '$1==k{print $2}' "$ALERTS" | tail -1)
  if [ -n "$last" ] && [ $(( NOW - last )) -lt $(( ALERT_REPEAT_HOURS * 3600 )) ]; then return 0; fi
  grep -v "^$1 " "$ALERTS" > "$ALERTS.tmp" 2>/dev/null; echo "$1 $NOW" >> "$ALERTS.tmp"; mv "$ALERTS.tmp" "$ALERTS"
  osascript -e "display notification \"${2//\"/}\" with title \"Agent Housekeeper\"" >/dev/null 2>&1
}

# ---- 2. log a line (every run, so we can see what grows over time) ----
if [ "$MODE" = run ]; then
  [ -f "$LOG" ] || echo "time,free_pct,swap_mb,top_apps_mb,top_single_processes_mb" > "$LOG"
  TOPPROCS=$(echo "$SNAP" | awk -F'\t' '$1=="PROC"{print $2"\t"$3}' | sort -rn | head -3 | awk -F'\t' '{printf "%s%s=%d", (NR>1?"; ":""), $2, $1}')
  echo "$STAMP,$FREE_PCT,$SWAP_MB,$(echo "$GROUPS_SORTED" | head -8 | awk -F'\t' '{printf "%s%s=%d", (NR>1?"; ":""), $2, $1}'),$TOPPROCS" >> "$LOG"
  if [ "$(wc -l < "$LOG")" -gt "$LOG_KEEP_LINES" ]; then tail -n "$LOG_KEEP_LINES" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; fi
fi

# ---- 3. alerts ----
ALERT_LINES=""
while IFS=$'\t' read -r m name; do
  [ -z "$m" ] && continue
  if [ "$m" -gt $(( APP_ALERT_GB * 1024 )) ]; then
    msg="$name is using $(gb "$m") GB of your ${TOTAL_GB} GB. Quit it (Cmd+Q) when you are between tasks, then reopen it."
    ALERT_LINES+="ALERT  $msg"$'\n'; [ "$MODE" = run ] && notify "app-${name//[^A-Za-z0-9]/_}" "$msg"
  fi
done <<< "$GROUPS_SORTED"
if [ -n "$SWAP_MB" ] && [ "$SWAP_MB" -gt $(( SWAP_ALERT_GB * 1024 )) ]; then
  msg="Your Mac has $(gb "$SWAP_MB") GB of memory parked on the disk, so it will feel slow. Biggest app: $(echo "$GROUPS_SORTED" | head -1 | cut -f2)."
  ALERT_LINES+="ALERT  $msg"$'\n'; [ "$MODE" = run ] && notify swap "$msg"
fi
if [ -n "$FREE_PCT" ] && [ "$FREE_PCT" -lt "$FREE_ALERT_PCT" ]; then
  msg="Only ${FREE_PCT}% memory free. Biggest app: $(echo "$GROUPS_SORTED" | head -1 | cut -f2)."
  ALERT_LINES+="ALERT  $msg"$'\n'; [ "$MODE" = run ] && notify lowfree "$msg"
fi

# ---- 4. agent sessions: track how long each has been idle ----
NEWSTATE=""; AGENT_LINES=""; ACT_LINES=""
while IFS=$'\t' read -r tag pid m c agemin auto parent cmd; do
  [ "$tag" = AGENT ] || continue
  key="$pid:$(echo "$cmd" | cut -c1-60 | tr ' \t' '__')"
  prev=$(awk -v k="$key" '$1==k{print $2, $3}' "$STATE")
  pc=${prev% *}; since=${prev#* }
  if [ -z "$prev" ] || awk -v a="$c" -v b="$pc" -v t="$IDLE_CPU_SECONDS" 'BEGIN{exit !(a-b >= t || a < b)}'; then since=$NOW; fi
  NEWSTATE+="$key $c $since"$'\n'
  idle=$(( (NOW - since) / 60 ))
  case " $MANAGED_BY_APP " in *" $parent "*) auto=0; kind="app-managed";; *)
    kind=$([ "$auto" = 1 ] && echo "automation run" || echo "interactive");; esac
  case "$cmd" in *" serve"*|*" server"*|*" daemon"*) auto=0; kind="service";; esac
  AGENT_LINES+="$(printf '  pid %-6s %-14s %5s GB  age %4sm  idle %4sm  in %s\n      %s' "$pid" "$kind" "$(gb "$m")" "$agemin" "$idle" "$parent" "$(echo "$cmd" | cut -c1-110)")"$'\n'
  protected=0; [ -n "$PROTECT_PATTERN" ] && echo "$cmd" | grep -qE "$PROTECT_PATTERN" && protected=1
  if [ "$auto" = 1 ] && [ "$protected" = 0 ] && [ "$idle" -ge "$IDLE_MINUTES" ] && [ "$agemin" -ge "$MIN_AGE_MINUTES" ]; then
    if [ "$CLOSE_IDLE_AUTOMATION" = 1 ] && [ "$MODE" = run ]; then
      kill -TERM "$pid" 2>/dev/null && ACT_LINES+="$STAMP closed finished automation run pid $pid (idle ${idle}m, $(gb "$m") GB): $(echo "$cmd" | cut -c1-120)"$'\n'
    else
      ACT_LINES+="$STAMP would close finished automation run pid $pid (idle ${idle}m, $(gb "$m") GB)"$'\n'
    fi
  fi
done <<< "$SNAP"
[ "$MODE" = run ] && printf '%s' "$NEWSTATE" > "$STATE"

# ---- 5. helpers left behind by agents that already exited ----
ORPHAN_LINES=""
while IFS=$'\t' read -r tag pid m agemin cmd; do
  [ "$tag" = ORPHAN ] || continue
  ORPHAN_LINES+="  pid $pid  $(gb "$m") GB  age ${agemin}m  $(echo "$cmd" | cut -c1-110)"$'\n'
  if [ "$CLOSE_ORPHANS" = 1 ] && [ "$MODE" = run ]; then
    kill -TERM "$pid" 2>/dev/null && ACT_LINES+="$STAMP closed left-behind helper pid $pid: $(echo "$cmd" | cut -c1-120)"$'\n'
  fi
done <<< "$SNAP"

if [ "$MODE" = run ]; then
  printf '%s' "$ACT_LINES" | grep -v 'would close' >> "$ACTIONS"
  exit 0
fi

# ---- 6. human-readable output for check / status ----
echo "Memory: ${FREE_PCT}% free of ${TOTAL_GB} GB, $(gb "${SWAP_MB:-0}") GB parked on disk (swap)"
echo; echo "Biggest apps (with their helpers):"
echo "$GROUPS_SORTED" | head -8 | awk -F'\t' '{printf "  %6.1f GB  %s\n", $1/1024, $2}'
echo; echo "Agent sessions:"; [ -n "$AGENT_LINES" ] && printf '%s' "$AGENT_LINES" || echo "  none running"
echo; echo "Helpers left behind by exited agents:"; [ -n "$ORPHAN_LINES" ] && printf '%s' "$ORPHAN_LINES" || echo "  none"
[ -n "$ALERT_LINES" ] && { echo; printf '%s' "$ALERT_LINES"; }
if [ "$MODE" = check ]; then
  echo; echo "What a scheduled run would do now:"; [ -n "$ACT_LINES" ] && printf '%s' "$ACT_LINES" || echo "  nothing"
  echo "  (closing finished runs is $([ "$CLOSE_IDLE_AUTOMATION" = 1 ] && echo ON || echo OFF); closing left-behind helpers is $([ "$CLOSE_ORPHANS" = 1 ] && echo ON || echo OFF))"
fi
if [ "$MODE" = status ]; then
  echo; echo "Last log lines ($LOG):"; tail -n 5 "$LOG" 2>/dev/null | sed 's/^/  /'
  echo; echo "Recent actions ($ACTIONS):"; tail -n 5 "$ACTIONS" 2>/dev/null | sed 's/^/  /'; [ -s "$ACTIONS" ] || echo "  none yet"
fi
