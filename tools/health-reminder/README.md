# Smart Health Reminder

This is a small macOS-only sedentary reminder. The source code stays in this
project folder. During install, a runtime copy is placed in
`~/Library/Application Support/lucerna-health-reminder` because launchd can be
restricted from reading shell scripts directly from external volumes.

## Behavior

- Runs every 5 minutes.
- Active only Monday-Friday, 09:30-18:30.
- Treats 10 minutes without keyboard/mouse activity as a real break.
- After 1 hour of continuous activity:
  - shows a macOS notification with sound,
  - after 2 more minutes of continued activity, speaks a voice reminder,
  - after 10 more minutes without a real break, shows a dialog with
    `我现在起身` and `延后 10 分钟`.
- Delays reminders for 10 minutes if these apps are frontmost:
  `zoom.us`, `腾讯会议`, `Microsoft Teams`, `FaceTime`, `Keynote`,
  `Microsoft PowerPoint`.

## Install

```sh
/Volumes/WorkSSD/codes/luma/tools/health-reminder/install.sh
```

## Check status

```sh
launchctl print gui/$(id -u)/com.lucerna.health-reminder
```

## Uninstall

```sh
/Volumes/WorkSSD/codes/luma/tools/health-reminder/uninstall.sh
```

The uninstall script removes the LaunchAgent plist and runtime script copy. It
leaves logs and state files in place so you can inspect them:

- `~/Library/Application Support/lucerna-health-reminder`
- `~/Library/Logs/lucerna-health-reminder`
