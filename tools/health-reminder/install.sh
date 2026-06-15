#!/bin/zsh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT_PATH="${SCRIPT_DIR}/sedentary_reminder.sh"
RUNTIME_DIR="${HOME}/Library/Application Support/lucerna-health-reminder"
RUNTIME_SCRIPT_PATH="${RUNTIME_DIR}/sedentary_reminder.sh"
TEMPLATE_PATH="${SCRIPT_DIR}/com.lucerna.health-reminder.plist.template"
PLIST_PATH="${HOME}/Library/LaunchAgents/com.lucerna.health-reminder.plist"
LOG_DIR="${HOME}/Library/Logs/lucerna-health-reminder"
LABEL="gui/$(id -u)/com.lucerna.health-reminder"

mkdir -p "${HOME}/Library/LaunchAgents" "${LOG_DIR}" "${RUNTIME_DIR}"
cp "${SOURCE_SCRIPT_PATH}" "${RUNTIME_SCRIPT_PATH}"
chmod +x "${SOURCE_SCRIPT_PATH}" "${RUNTIME_SCRIPT_PATH}"

sed \
  -e "s#__SCRIPT_PATH__#${RUNTIME_SCRIPT_PATH}#g" \
  -e "s#__LOG_DIR__#${LOG_DIR}#g" \
  "${TEMPLATE_PATH}" > "${PLIST_PATH}"

launchctl bootout "${LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}"
launchctl enable "${LABEL}"
launchctl kickstart -k "${LABEL}"

echo "Installed ${PLIST_PATH}"
echo "Runtime copy: ${RUNTIME_SCRIPT_PATH}"
echo "Logs: ${LOG_DIR}"
