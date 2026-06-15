#!/bin/zsh
set -eu

PLIST_PATH="${HOME}/Library/LaunchAgents/com.lucerna.health-reminder.plist"
RUNTIME_SCRIPT_PATH="${HOME}/Library/Application Support/lucerna-health-reminder/sedentary_reminder.sh"
LABEL="gui/$(id -u)/com.lucerna.health-reminder"

launchctl bootout "${LABEL}" >/dev/null 2>&1 || true
rm -f "${PLIST_PATH}"
rm -f "${RUNTIME_SCRIPT_PATH}"

echo "Removed ${PLIST_PATH}"
echo "Removed ${RUNTIME_SCRIPT_PATH}"
echo "State/logs were left in place:"
echo "  ${HOME}/Library/Application Support/lucerna-health-reminder"
echo "  ${HOME}/Library/Logs/lucerna-health-reminder"
