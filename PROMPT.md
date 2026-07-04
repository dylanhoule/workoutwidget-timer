# Build: Workout Interval — macOS Menu Bar App

You are building a small, polished macOS menu bar (tray) app. Work in the current
directory. Local-only: no network, no accounts, no analytics.

## What it does
I work at my desk and want to be reminded to exercise at a fixed interval
(e.g., every hour: 15 pushups + 15 situps), and to track how much I've done.

## Requirements

**Menu bar presence**
- Lives only in the menu bar (`LSUIElement`, no Dock icon). Icon + popover UI
  (SwiftUI `MenuBarExtra`, `.window` style).
- Icon reflects state: idle / running / "exercises due".

**Timer**
- Configurable interval, default 60 min. Start / pause / reset in one click
  from the popover.
- When it fires: system notification + attention state on the icon. After the
  exercises are logged, the timer restarts automatically.

**Exercises (customizable)**
- Each exercise: name + target reps. Defaults: Pushups 15, Situps 15.
  Add / edit / remove.
- When due, the popover shows a checklist: one tap logs an exercise at target
  reps; allow adjusting the count before logging (did 10 instead of 15).
  Skipping is allowed and logs nothing.

**Stats**
- Session totals (since launch, with a manual reset) and lifetime totals:
  reps per exercise, plus completed rounds. Shown in the popover, glanceable.
  No charts in v1.

**Persistence**
- Settings, exercises, and lifetime stats survive relaunch. JSON in
  `~/Library/Application Support/<app>/` is fine. No database.

**Look & feel**
- Follows system light/dark mode automatically; verify both.
- Native, clean, visually appealing: clear countdown, one obvious primary
  action, a satisfying "done" interaction. SF Symbols for icons.

## Tech constraints
- Swift + SwiftUI, `MenuBarExtra`, target macOS 13+. No third-party
  dependencies.
- `UNUserNotificationCenter` only works from a bundled `.app` with a bundle
  ID — structure the build so notifications actually work (a plain
  `swift run` executable can't register for them).
- If any tooling chokes on the `:` in this directory's path, stop and say so
  instead of fighting it.

## Out of scope — do not build
Cloud sync, accounts, profiles, charts, gamification, onboarding, settings
beyond what's listed.

## Acceptance — verify all before you're done
1. Build succeeds; app appears in the menu bar only (no Dock icon).
2. Set a 1-minute test interval → start → notification fires → log both
   default exercises → session and lifetime totals update.
3. Quit and relaunch → lifetime totals and custom exercises persist; session
   totals reset.
4. Add "Squats 20", remove an exercise, change the interval — all persist.
5. UI looks right in both dark and light mode.

Keep it minimal: the fewest files that stay readable, no speculative
abstractions.
