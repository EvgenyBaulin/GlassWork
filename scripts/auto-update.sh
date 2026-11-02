#!/usr/bin/env bash
# Rebuilds GlassWork from the latest main branch and reinstalls it into /Applications.
#
#   auto-update.sh run [--force]   rebuild if the last build is older than GW_UPDATE_DAYS (default 5)
#   auto-update.sh enable          install a LaunchAgent that runs `run` every day at 12:00
#   auto-update.sh disable         remove the LaunchAgent
#   auto-update.sh status          show the last build time and the log tail
#
# The build uses a separate checkout, so unfinished local work is never installed.
# Signing team: GW_TEAM, or DEVELOPMENT_TEAM from Config/Local.xcconfig of this checkout.
set -euo pipefail

REPO_URL="${GW_REPO_URL:-https://github.com/EvgenyBaulin/GlassWork.git}"
STATE_DIR="$HOME/Library/Application Support/GlassWork/AutoUpdate"
SRC_DIR="$STATE_DIR/src"
STAMP="$STATE_DIR/last-build"
LOG="$STATE_DIR/auto-update.log"
LABEL="io.github.evgenybaulin.glasswork.autoupdate"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DAYS="${GW_UPDATE_DAYS:-5}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

team() {
    if [[ -n "${GW_TEAM:-}" ]]; then echo "$GW_TEAM"; return; fi
    sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$HERE/Config/Local.xcconfig" 2>/dev/null | head -1 || true
}

due() {
    [[ ! -f "$STAMP" ]] && return 0
    local age=$(( $(date +%s) - $(stat -f %m "$STAMP") ))
    (( age >= DAYS * 86400 ))
}

run() {
    mkdir -p "$STATE_DIR"
    if [[ "${1:-}" != "--force" ]] && ! due; then
        return 0
    fi
    local team_id
    team_id="$(team || true)"
    [[ -n "$team_id" ]] || { log "no signing team (set GW_TEAM or Config/Local.xcconfig)"; exit 1; }

    log "update started"
    if [[ -d "$SRC_DIR/.git" ]]; then
        git -C "$SRC_DIR" fetch --quiet origin main
        git -C "$SRC_DIR" reset --quiet --hard origin/main
    else
        git clone --quiet --branch main "$REPO_URL" "$SRC_DIR"
    fi
    printf 'DEVELOPMENT_TEAM = %s\n' "$team_id" > "$SRC_DIR/Config/Local.xcconfig"

    local was_running=0
    pgrep -xq GlassWork && was_running=1
    (
        cd "$SRC_DIR"
        xcodegen generate --quiet
        xcodebuild -project GlassWork.xcodeproj -scheme GlassWork -configuration Release \
            -derivedDataPath build/DerivedData -destination 'generic/platform=macOS' \
            -allowProvisioningUpdates -quiet build
    ) >> "$LOG" 2>&1 || { log "build failed, installed app left as is"; exit 1; }

    pkill -x GlassWork || true
    rm -rf /Applications/GlassWork.app
    cp -R "$SRC_DIR/build/DerivedData/Build/Products/Release/GlassWork.app" /Applications/
    touch "$STAMP"
    (( was_running )) && open /Applications/GlassWork.app
    log "update finished at $(git -C "$SRC_DIR" rev-parse --short HEAD)"
}

enable() {
    mkdir -p "$STATE_DIR" "$(dirname "$PLIST")"
    local script="$STATE_DIR/auto-update.sh"
    cp "$HERE/scripts/auto-update.sh" "$script"
    chmod +x "$script"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$script</string><string>run</string></array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>GW_TEAM</key><string>$(team)</string>
        <key>GW_UPDATE_DAYS</key><string>$DAYS</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>12</integer><key>Minute</key><integer>0</integer></dict>
    <key>LowPriorityIO</key><true/>
    <key>Nice</key><integer>10</integer>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    log "auto-update enabled: checks daily at 12:00, rebuilds every $DAYS days"
}

disable() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    log "auto-update disabled"
}

status() {
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then echo "LaunchAgent: on"; else echo "LaunchAgent: off"; fi
    if [[ -f "$STAMP" ]]; then echo "Last build: $(date -r "$(stat -f %m "$STAMP")" '+%Y-%m-%d %H:%M')"; else echo "Last build: never"; fi
    [[ -f "$LOG" ]] && tail -5 "$LOG"
}

case "${1:-}" in
    run) shift; run "$@" ;;
    enable) enable ;;
    disable) disable ;;
    status) status ;;
    *) sed -n '2,10p' "$0"; exit 1 ;;
esac
