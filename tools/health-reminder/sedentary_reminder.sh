#!/bin/zsh
set -u

# Smart sedentary reminder for macOS.
# The code lives in this project; launchd only calls this script every 5 minutes.

ACTIVE_THRESHOLD_SECONDS=3600
REST_THRESHOLD_SECONDS=600
COOLDOWN_SECONDS=2700
VOICE_ESCALATION_AFTER_SECONDS=120
DIALOG_ESCALATION_AFTER_SECONDS=600

WORK_START_HHMM="09:30"
WORK_END_HHMM="18:30"
WORK_DAYS="1,2,3,4,5"

TITLE="健康微休息"
MESSAGE="你已经连续在电脑前工作 1 小时。现在站起来活动 10 分钟：护腰 + 力量 + 远眺。"
VOICE_MESSAGE="该站起来活动十分钟了。先离开屏幕，做护腰、力量和远眺。"

# If one of these apps is frontmost, the reminder is delayed to avoid meetings/presentations.
DEFER_FRONTMOST_APPS=("zoom.us" "腾讯会议" "Microsoft Teams" "FaceTime" "Keynote" "Microsoft PowerPoint")

STATE_DIR="${HOME}/Library/Application Support/lucerna-health-reminder"
STATE_FILE="${STATE_DIR}/state.env"
LOCK_DIR="${STATE_DIR}/run.lock"

mkdir -p "${STATE_DIR}"

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

now_epoch() {
  date +%s
}

idle_seconds() {
  ioreg -c IOHIDSystem | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }'
}

hhmm_to_minutes() {
  local value="$1"
  local hh="${value%%:*}"
  local mm="${value##*:}"
  echo $((10#$hh * 60 + 10#$mm))
}

within_work_window() {
  local weekday current_minutes start_minutes end_minutes
  weekday="$(date +%u)"
  if [[ ",${WORK_DAYS}," != *",${weekday},"* ]]; then
    return 1
  fi

  current_minutes=$((10#$(date +%H) * 60 + 10#$(date +%M)))
  start_minutes="$(hhmm_to_minutes "${WORK_START_HHMM}")"
  end_minutes="$(hhmm_to_minutes "${WORK_END_HHMM}")"

  [[ "${current_minutes}" -ge "${start_minutes}" && "${current_minutes}" -le "${end_minutes}" ]]
}

frontmost_app() {
  osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || true
}

should_defer_for_frontmost_app() {
  local app="$1"
  local item
  for item in "${DEFER_FRONTMOST_APPS[@]}"; do
    if [[ "${app}" == "${item}" ]]; then
      return 0
    fi
  done
  return 1
}

load_state() {
  active_since=0
  last_alert_at=0
  snooze_until=0

  if [[ -f "${STATE_FILE}" ]]; then
    source "${STATE_FILE}"
  fi
}

save_state() {
  {
    printf 'active_since=%s\n' "${active_since:-0}"
    printf 'last_alert_at=%s\n' "${last_alert_at:-0}"
    printf 'snooze_until=%s\n' "${snooze_until:-0}"
  } > "${STATE_FILE}"
}

reset_active_clock() {
  active_since=0
  save_state
}

notify_user() {
  osascript -e "display notification \"${MESSAGE}\" with title \"${TITLE}\" sound name \"Submarine\"" >/dev/null 2>&1 || true
  afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 || true
}

speak_user() {
  say "${VOICE_MESSAGE}" >/dev/null 2>&1 || true
}

dialog_user() {
  local result
  result="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
set dialogText to "你已经连续在电脑前工作超过 1 小时，而且提醒后仍未休息。现在站起来活动 10 分钟。"
display dialog dialogText buttons {"我现在起身", "延后 10 分钟"} default button "我现在起身" with title "健康微休息" giving up after 120
if gave up of result then
  return "gave-up"
else
  return button returned of result
end if
APPLESCRIPT
)"

  load_state
  local now
  now="$(now_epoch)"
  case "${result}" in
    *"延后 10 分钟"*)
      snooze_until=$((now + 600))
      ;;
    *)
      active_since=0
      snooze_until=$((now + 600))
      ;;
  esac
  save_state
}

load_state
now="$(now_epoch)"

if ! within_work_window; then
  reset_active_clock
  exit 0
fi

if [[ "${now}" -lt "${snooze_until:-0}" ]]; then
  exit 0
fi

front_app="$(frontmost_app)"
if should_defer_for_frontmost_app "${front_app}"; then
  snooze_until=$((now + 600))
  save_state
  exit 0
fi

idle="$(idle_seconds)"
if [[ -z "${idle}" ]]; then
  exit 0
fi

if [[ "${idle}" -ge "${REST_THRESHOLD_SECONDS}" ]]; then
  reset_active_clock
  exit 0
fi

if [[ "${active_since:-0}" -le 0 ]]; then
  active_since=$((now - idle))
  save_state
fi

active_duration=$((now - active_since))
since_last_alert=$((now - ${last_alert_at:-0}))

if [[ "${active_duration}" -lt "${ACTIVE_THRESHOLD_SECONDS}" ]]; then
  exit 0
fi

if [[ "${since_last_alert}" -lt "${COOLDOWN_SECONDS}" ]]; then
  exit 0
fi

notify_user
last_alert_at="${now}"
save_state

sleep "${VOICE_ESCALATION_AFTER_SECONDS}"
idle_after_voice_wait="$(idle_seconds)"
if [[ "${idle_after_voice_wait}" -lt "${VOICE_ESCALATION_AFTER_SECONDS}" ]]; then
  speak_user
fi

remaining_dialog_wait=$((DIALOG_ESCALATION_AFTER_SECONDS - VOICE_ESCALATION_AFTER_SECONDS))
if [[ "${remaining_dialog_wait}" -gt 0 ]]; then
  sleep "${remaining_dialog_wait}"
fi

idle_after_dialog_wait="$(idle_seconds)"
if [[ "${idle_after_dialog_wait}" -lt "${REST_THRESHOLD_SECONDS}" ]]; then
  dialog_user
fi
