# TaskAlarm — iOS Alarm App Design

**Date:** 2026-06-10
**Status:** Approved by user (brainstorming session)

## Problem

The built-in iOS alarm is too easy to silence: one tap and you're back asleep. TaskAlarm makes dismissing (and snoozing) an alarm conditional on completing a task that requires being awake — scanning a QR code placed in another room, or typing a phrase exactly.

## Goals

- Real alarm behavior: rings through silent mode and Focus, rings when the app is closed, survives reboot.
- Dismiss **and** snooze are both gated behind a task. No free escape.
- Initial audience: the author and colleagues (sideload/TestFlight). Later: App Store release, so only App Store-safe APIs are used.

## Non-Goals (v1)

- Custom alarm sounds, gradual volume, alarm history/stats, streaks.
- Support for iOS versions below 26 (no notification-stack fallback).
- Android or any non-iOS platform.

## Key Constraint

AlarmKit (iOS 26+) provides true system alarms for third-party apps, but Apple **requires** a Stop button on the system alert UI. It cannot be removed. The app therefore enforces the task gate with a **re-arm guard loop**: stopping the alarm without completing the task only buys ~90 seconds of silence before it rings again.

## Approach (chosen: A — AlarmKit + re-arm guard loop)

Alternatives considered and rejected:

- **B — Notification stack (iOS 15+):** 50+ chained 30-second notification sounds. Rejected: the silent switch mutes it entirely, breaking the core promise.
- **C — AlarmKit countdown chaining:** model alarms as repeating countdowns. Rejected: Stop still fully kills the alarm, and countdown semantics fit timers, not wake-up alarms.

### Alarm fire flow

1. AlarmKit fires the alarm (system UI, breaks silent mode, works with app killed).
2. System alert shows two buttons:
   - **"Solve task"** (custom button) → opens the app → `TaskGateView` → task passed → alarm stopped for real, then user chooses Dismiss or Snooze.
   - **"Stop"** (Apple-required) → the app's alarm state observer detects a stop without task completion → writes `PendingTaskState` → schedules a guard alarm **+90 seconds** → rings again. Loops until the task is completed.
3. Snooze (after task only): schedules a new AlarmKit alarm +9 minutes. Maximum 3 snoozes per alarm fire, then dismiss-only.

`PendingTaskState` is persisted in SwiftData, so a force-killed app still resumes the gate loop on relaunch — and the AlarmKit guard alarm rings regardless because it is system-scheduled.

## Tech Stack

- Swift + SwiftUI, iOS 26+
- **AlarmKit** — alarm scheduling, system alert UI, state observation
- **VisionKit** (`DataScannerViewController`) — QR scanning
- **CoreImage** (`CIQRCodeGenerator`) — QR generation
- **SwiftData** — persistence

## Architecture

```
┌────────────────────────────────────────────┐
│                 SwiftUI App                │
│  AlarmListView ── AlarmEditView            │
│        │                                   │
│  TaskGateView (QR scan / phrase type)      │
├────────┼───────────────────────────────────┤
│  AlarmScheduler (wraps AlarmKit)           │
│   • schedule / cancel / stop alarms        │
│   • observe alarm state changes            │
│   • re-arm guard: cheat-stop → +90s alarm  │
├────────────────────────────────────────────┤
│  TaskEngine                                │
│   • QRTask: validate scan against payload  │
│   • PhraseTask: random phrase, exact match │
│   • fallback timer: 2 min fail → phrase    │
├────────────────────────────────────────────┤
│  Storage (SwiftData)                       │
│   • Alarm, QRCodeRecord, PendingTaskState  │
└────────────────────────────────────────────┘
```

## Components

### Views (SwiftUI)

- `AlarmListView` — home screen; alarm rows, enable/disable toggle, add button.
- `AlarmEditView` — time picker, weekday repeat selector, label, task type picker (QR / phrase).
- `TaskGateView` — container shown when an alarm is ringing; routes to the active task and shows the fallback option when available.
- `QRScanView` — camera scanner; validates scanned payload against the stored `QRCodeRecord`.
- `PhraseTaskView` — displays a random ~8-word phrase; user must retype it exactly. Paste is disabled; the phrase re-randomizes on each failed attempt.
- `QRSetupView` — generates the QR code and presents a share/print sheet. Runs during alarm setup when the QR task is selected and no code exists yet.
- `PostTaskView` — shown after the task passes; offers **Dismiss** or **Snooze 9 min** (if snoozes remain).

### Services

- `AlarmScheduler` — sole AlarmKit wrapper. Schedules weekday-repeating alarms, guard alarms, and snooze alarms. Observes the AlarmKit alarm-updates stream; a system Stop without a task-completion flag triggers the guard re-arm. Exposed behind a protocol so tests can mock it (real AlarmKit requires a device).
- `TaskEngine` — `protocol DismissTask { func validate(input) -> Bool }` with `QRTask` and `PhraseTask` implementations. Owns the 2-minute fallback timer (failed/absent QR scan → offer phrase task).

### Data model (SwiftData)

```swift
@Model class Alarm {
    var id: UUID
    var time: Date            // hour + minute used
    var weekdays: Set<Int>    // empty = one-shot
    var label: String
    var isEnabled: Bool
    var taskType: TaskType    // .qrScan or .phrase
    var alarmKitID: UUID?     // link to the scheduled AlarmKit alarm
}

@Model class QRCodeRecord {
    var payload: String       // "wakeup-<uuid>"
    var createdAt: Date
}

@Model class PendingTaskState {
    var alarmID: UUID
    var firedAt: Date
    var guardCount: Int       // number of re-arms so far
}
```

One QR code is global, not per-alarm: print once, stick it on the wall, every QR alarm uses it. Settings offers regeneration (which invalidates the old code).

## Edge Cases & Error Handling

**Permissions**

- AlarmKit authorization is requested on first alarm creation. If denied, a blocking screen explains why the app cannot work and links to Settings.
- Camera permission is requested on first QR task use. If denied, the alarm auto-falls back to the phrase task — no dead end.

**Cheat and failure paths**

| Case | Handling |
|---|---|
| System Stop pressed, no task done | Guard alarm +90 s, `guardCount` increments, loop continues |
| App force-killed during ring | AlarmKit rings anyway (system-level); `PendingTaskState` survives in SwiftData, relaunch resumes the gate |
| QR paper lost / camera failure | After 2 minutes in the scan view without a valid scan, a "Type phrase instead" button appears |
| Phone reboot overnight | AlarmKit alarms persist across reboot (system behavior) |
| User deletes the app | No defense possible; acknowledged openly ("deleting the app is the only escape") |
| Infinite snooze after task | Maximum 3 snoozes per alarm fire, then dismiss-only |
| Phrase paste cheat | Paste disabled in the text field; phrase re-randomized per attempt |
| Guard alarm spam (phone left at home) | `guardCount` capped at 20 (~30 minutes), then the alarm gives up and is marked "missed" |

**Time edge cases**

- One-shot alarm dismissed → its toggle auto-disables.
- Weekday repeats are handled by AlarmKit's recurring schedule.
- Timezone changes: AlarmKit alarms use wall-clock time; the system handles adjustment.

## Testing

- **Unit (XCTest, no device):** `TaskEngine` validation (phrase exact-match, QR payload match), guard-count logic, snooze-limit logic.
- **Mocked scheduler:** `AlarmScheduler` sits behind a protocol; AlarmKit is mocked in unit tests since the real framework needs hardware.
- **Manual device matrix:** ring in silent mode; ring with app killed; Stop-button cheat → 90 s re-ring; reboot persistence.
- **UI tests:** alarm create → edit → toggle flow.

## Open Items for Implementation Planning

- Verify exact AlarmKit API surface (observer stream names, schedule/recurrence types, custom-button App Intent wiring) against current Apple documentation — the framework is new and the design uses approximate names.
- Confirm whether AlarmKit's custom alert button can deep-link directly into `TaskGateView` via an App Intent.
