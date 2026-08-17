# Task Reminder

Flutter task reminder app based on the visual language and account/sync/update
flow of `../money-manager`.

## Features

- Login, register, and password update through the local backend.
- Two-way sync through `/api/task-reminder/data`.
- APK update check through `/api/update/latest`.
- Local notification permission and scheduled reminders for pending tasks.
- Overview tab: 30-day calendar with green done counts and red pending counts.
- Daily tab: My Day focus queue, progress, streak, estimated minutes, priority sorting, and quick snooze.
- Work list tab: smart Quick Add, add/delete work items, manage today's list, and show the 5 most frequent tasks with More.
- Account tab: backend URL, sync, notifications, update check, password change, and logout.

## Product Survey

The new convenience features were selected from common patterns in leading
reminder apps:

- Todoist: natural-language quick add, recurring schedules, priority metadata.
- TickTick: all-in-one task, calendar, habit, and focus workflow.
- Microsoft To Do: My Day daily planning and suggested daily focus.
- Google Tasks: date/time tasks that appear in calendar-style planning.
- Apple Reminders and Any.do: simple reminders, categorized lists, and daily planner habits.

## New Convenience Features

- Smart Quick Add: type `Nộp báo cáo mai 9:30 !cao ~45p #laptop` to create a
  clean task title, schedule tomorrow, set the reminder time, priority,
  estimate, and icon.
- My Day focus queue: today's tasks are sorted by priority, reminder time, and
  duration so urgent work surfaces first.
- Snooze controls: push a task by 15 minutes or move it to tomorrow from the
  daily card without editing the task.
- Effort planning: each task stores an estimated duration and shows total focus
  minutes for today.
- Habit streak: Daily shows the current streak of days with completed tasks.

## Run

```bash
flutter pub get
flutter run
```

## Backend

```bash
cd backend
npm install
ALLOWED_ORIGINS=http://192.168.1.137:8080 npm start
```

The backend listens on port `3002` by default and writes runtime data under
`backend/server-data/`, which should be backed up separately.

Useful release environment variables:

- `PORT`: backend port, default `3002`.
- `DATA_DIR`: runtime data directory, default `backend/server-data/`.
- `ALLOWED_ORIGINS`: comma-separated web origins allowed by CORS.
- `ALLOW_INSECURE_PASSWORD_RESET`: set to `1` only for temporary local recovery;
  leave unset for release. Users should change passwords after signing in.

Security hardening included for release:

- Passwords must be at least 8 characters.
- Public password reset is disabled by default.
- Auth endpoints are rate-limited in memory.
- CORS only echoes origins listed in `ALLOWED_ORIGINS`.
- Security headers are set on backend responses.
- Sync payloads are size-limited and sanitized before persistence.
- Android debug builds allow local HTTP for LAN testing; release builds block
  cleartext traffic and should use an HTTPS backend URL.

Release notes:

- `flutter build apk --release` creates `build/app/outputs/flutter-apk/app-release.apk`.
- The release build is intentionally unsigned in this checkout. Sign it with the
  real release key before publishing or uploading to the backend update channel.

## Browser Preview

```bash
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Open `http://192.168.1.137:8080` and use backend
`http://192.168.1.137:3002`.

## Validate

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
cd backend && npm audit --audit-level=moderate && npm test
flutter build apk --debug
```
