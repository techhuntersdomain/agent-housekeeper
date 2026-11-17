#!/bin/bash
# Installs agent-housekeeper so macOS runs it every 10 minutes (via launchd, the Mac's built-in scheduler).
#   install.sh              install or update
#   install.sh uninstall    stop it and remove the schedule (keeps your logs and config)
set -eu
LABEL="com.agent-housekeeper"
DATA="${AH_HOME:-$HOME/.agent-housekeeper}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC="$(cd "$(dirname "$0")" && pwd)"
INTERVAL="${AH_INTERVAL_SECONDS:-600}"

if [ "${1:-}" = uninstall ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Stopped and removed the schedule. Logs and config are still in $DATA"
  exit 0
fi

[ "$(uname)" = Darwin ] || { echo "agent-housekeeper only runs on macOS."; exit 1; }
mkdir -p "$DATA/bin" "$HOME/Library/LaunchAgents"
cp "$SRC/housekeeper.sh" "$DATA/bin/housekeeper.sh"
chmod +x "$DATA/bin/housekeeper.sh"
[ -f "$DATA/config.env" ] || cp "$SRC/../config.example.env" "$DATA/config.env"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$DATA/bin/housekeeper.sh</string><string>run</string></array>
  <key>EnvironmentVariables</key><dict><key>AH_HOME</key><string>$DATA</string></dict>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>Nice</key><integer>10</integer>
  <key>StandardOutPath</key><string>$DATA/launchd.log</string>
  <key>StandardErrorPath</key><string>$DATA/launchd.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed. It checks every $((INTERVAL / 60)) minutes."
echo "  Settings: $DATA/config.env"
echo "  See what it sees: $DATA/bin/housekeeper.sh status"
