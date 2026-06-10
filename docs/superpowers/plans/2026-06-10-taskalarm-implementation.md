# TaskAlarm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS alarm app where dismissing or snoozing an alarm requires completing a task (QR scan or phrase typing); pressing the system Stop button without the task only buys ~90 seconds before the alarm re-arms.

**Architecture:** SwiftUI app on iOS 26+. AlarmKit provides real system alarms (breaks silent mode, works app-killed). The Apple-required Stop button carries a custom `stopIntent` that detects cheat-stops and schedules a guard alarm +90 s. A `.custom` secondary button opens the app into the task gate. Pure-logic policies (guard, snooze, task validation) are unit-tested; AlarmKit sits behind a protocol and is mocked in tests.

**Tech Stack:** Swift 6, SwiftUI, AlarmKit, App Intents (`LiveActivityIntent`), VisionKit (`DataScannerViewController`), CoreImage (`CIQRCodeGenerator`), SwiftData, Swift Testing (`import Testing`).

**Spec:** `docs/superpowers/specs/2026-06-10-alarm-app-design.md`

---

## File Structure

```
TaskAlarm/
├── TaskAlarm.xcodeproj
├── TaskAlarm/
│   ├── TaskAlarmApp.swift            # app entry, container, router
│   ├── AppRouter.swift               # observable: which screen to force (task gate)
│   ├── Models/
│   │   ├── TaskType.swift            # enum .qrScan / .phrase
│   │   ├── Alarm.swift               # @Model AlarmItem (avoid name clash with AlarmKit.Alarm)
│   │   ├── QRCodeRecord.swift        # @Model
│   │   └── PendingTaskState.swift    # @Model
│   ├── Logic/
│   │   ├── PhraseTask.swift          # phrase generation + validation
│   │   ├── QRTask.swift              # payload generation + validation
│   │   ├── GuardPolicy.swift         # 90s interval, cap 20, give-up
│   │   └── SnoozePolicy.swift        # 9 min, max 3
│   ├── Scheduling/
│   │   ├── AlarmScheduling.swift     # protocol
│   │   └── AlarmKitScheduler.swift   # AlarmKit wrapper (device-only paths)
│   ├── Intents/
│   │   ├── OpenTaskGateIntent.swift  # secondary button → open app
│   │   └── StopWithoutTaskIntent.swift # stop button → cheat detect + guard
│   └── Views/
│       ├── AlarmListView.swift
│       ├── AlarmEditView.swift
│       ├── TaskGateView.swift
│       ├── QRScanView.swift
│       ├── PhraseTaskView.swift
│       ├── QRSetupView.swift
│       ├── PostTaskView.swift
│       └── AuthorizationBlockedView.swift
└── TaskAlarmTests/
    ├── PhraseTaskTests.swift
    ├── QRTaskTests.swift
    ├── GuardPolicyTests.swift
    ├── SnoozePolicyTests.swift
    └── ModelTests.swift
```

Naming note: the SwiftData model is `AlarmItem` because `AlarmKit` exports a type named `Alarm`; sharing the name would force qualification everywhere.

---

### Task 1: Xcode project scaffold

**Files:**
- Create: `TaskAlarm.xcodeproj` (via Xcode GUI)
- Modify: target Info settings

No TDD here — scaffold only.

- [ ] **Step 1: Create project in Xcode**

Xcode → File → New → Project → iOS App:
- Product Name: `TaskAlarm`
- Interface: SwiftUI, Language: Swift
- Storage: SwiftData (checkbox)
- Testing System: Swift Testing
- Location: `/Users/niteshdas/Projects/taskalarm-ios/` (uncheck "create git repository" — repo exists)

- [ ] **Step 2: Set deployment target and capabilities**

Target → General → Minimum Deployments: **iOS 26.0**.

Target → Info tab, add keys:
- `NSAlarmKitUsageDescription` = `TaskAlarm needs permission to schedule alarms that ring even in silent mode.`
- `NSCameraUsageDescription` = `TaskAlarm uses the camera to scan your wake-up QR code.`

- [ ] **Step 3: Verify it builds and tests run**

Run: `xcodebuild -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: `TEST SUCCEEDED` (template test passes)

- [ ] **Step 4: Delete template content, commit**

Delete the template `Item.swift` and its references in `TaskAlarmApp.swift`/`ContentView.swift` (leave a minimal `ContentView` with `Text("TaskAlarm")`). Delete the template test function body, keep the test file.

```bash
git add -A
git commit -m "chore: scaffold TaskAlarm Xcode project (iOS 26, SwiftUI, SwiftData)"
```

---

### Task 2: Core models

**Files:**
- Create: `TaskAlarm/Models/TaskType.swift`
- Create: `TaskAlarm/Models/Alarm.swift`
- Create: `TaskAlarm/Models/QRCodeRecord.swift`
- Create: `TaskAlarm/Models/PendingTaskState.swift`
- Test: `TaskAlarmTests/ModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// TaskAlarmTests/ModelTests.swift
import Testing
import SwiftData
@testable import TaskAlarm

@MainActor
struct ModelTests {
    func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: AlarmItem.self, QRCodeRecord.self, PendingTaskState.self,
            configurations: config)
    }

    @Test func alarmItemRoundTrips() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let alarm = AlarmItem(hour: 7, minute: 30, weekdays: [2, 3, 4, 5, 6],
                              label: "Work", taskType: .qrScan)
        context.insert(alarm)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AlarmItem>())
        #expect(fetched.count == 1)
        #expect(fetched[0].hour == 7)
        #expect(fetched[0].minute == 30)
        #expect(fetched[0].weekdays == [2, 3, 4, 5, 6])
        #expect(fetched[0].taskType == .qrScan)
        #expect(fetched[0].isEnabled == true)
    }

    @Test func pendingTaskStateTracksGuardCount() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = PendingTaskState(alarmID: UUID(), firedAt: .now)
        context.insert(pending)
        #expect(pending.guardCount == 0)
        pending.guardCount += 1
        #expect(pending.guardCount == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20`
Expected: FAIL — `cannot find 'AlarmItem' in scope`

- [ ] **Step 3: Write the models**

```swift
// TaskAlarm/Models/TaskType.swift
import Foundation

enum TaskType: String, Codable, CaseIterable, Identifiable {
    case qrScan
    case phrase

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qrScan: "Scan QR code"
        case .phrase: "Type a phrase"
        }
    }
}
```

```swift
// TaskAlarm/Models/Alarm.swift
import Foundation
import SwiftData

@Model
final class AlarmItem {
    var id: UUID
    var hour: Int
    var minute: Int
    /// Calendar weekday numbers, 1 = Sunday … 7 = Saturday. Empty = one-shot.
    var weekdays: [Int]
    var label: String
    var isEnabled: Bool
    var taskType: TaskType
    /// ID of the currently scheduled AlarmKit alarm, if any.
    var alarmKitID: UUID?

    init(id: UUID = UUID(), hour: Int, minute: Int, weekdays: [Int] = [],
         label: String = "", isEnabled: Bool = true, taskType: TaskType = .phrase) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.label = label
        self.isEnabled = isEnabled
        self.taskType = taskType
    }
}
```

```swift
// TaskAlarm/Models/QRCodeRecord.swift
import Foundation
import SwiftData

@Model
final class QRCodeRecord {
    var payload: String
    var createdAt: Date

    init(payload: String, createdAt: Date = .now) {
        self.payload = payload
        self.createdAt = createdAt
    }
}
```

```swift
// TaskAlarm/Models/PendingTaskState.swift
import Foundation
import SwiftData

@Model
final class PendingTaskState {
    var alarmID: UUID
    var firedAt: Date
    var guardCount: Int
    /// AlarmKit ID of the currently scheduled guard alarm, if any.
    var guardAlarmKitID: UUID?
    var snoozesUsed: Int

    init(alarmID: UUID, firedAt: Date, guardCount: Int = 0, snoozesUsed: Int = 0) {
        self.alarmID = alarmID
        self.firedAt = firedAt
        self.guardCount = guardCount
        self.snoozesUsed = snoozesUsed
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add TaskAlarm/Models TaskAlarmTests/ModelTests.swift
git commit -m "feat: add SwiftData models (AlarmItem, QRCodeRecord, PendingTaskState)"
```

---

### Task 3: PhraseTask logic

**Files:**
- Create: `TaskAlarm/Logic/PhraseTask.swift`
- Test: `TaskAlarmTests/PhraseTaskTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// TaskAlarmTests/PhraseTaskTests.swift
import Testing
@testable import TaskAlarm

struct PhraseTaskTests {
    @Test func generatesEightWords() {
        let phrase = PhraseTask.generate()
        #expect(phrase.split(separator: " ").count == 8)
    }

    @Test func generatedPhrasesDiffer() {
        // 50-word pool, 8 picks: collision over 5 runs is effectively impossible.
        let phrases = (0..<5).map { _ in PhraseTask.generate() }
        #expect(Set(phrases).count > 1)
    }

    @Test func validateAcceptsExactMatch() {
        #expect(PhraseTask.validate(input: "red fox jumps", against: "red fox jumps"))
    }

    @Test func validateTrimsOuterWhitespaceOnly() {
        #expect(PhraseTask.validate(input: "  red fox jumps \n", against: "red fox jumps"))
    }

    @Test func validateRejectsCaseMismatch() {
        #expect(!PhraseTask.validate(input: "Red fox jumps", against: "red fox jumps"))
    }

    @Test func validateRejectsMissingWord() {
        #expect(!PhraseTask.validate(input: "red fox", against: "red fox jumps"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PhraseTask' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// TaskAlarm/Logic/PhraseTask.swift
import Foundation

enum PhraseTask {
    static let wordPool: [String] = [
        "anchor", "basket", "candle", "dragon", "ember", "falcon", "garden",
        "hammer", "island", "jacket", "kettle", "lantern", "marble", "needle",
        "orange", "pebble", "quiver", "ribbon", "saddle", "timber", "umbrella",
        "violet", "walnut", "yellow", "zipper", "bridge", "copper", "desert",
        "engine", "forest", "guitar", "harbor", "iceberg", "jungle", "kitten",
        "ladder", "magnet", "nectar", "ocean", "pencil", "quartz", "rocket",
        "silver", "tunnel", "valley", "window", "garlic", "helmet", "insect", "jigsaw"
    ]

    static func generate() -> String {
        wordPool.shuffled().prefix(8).joined(separator: " ")
    }

    static func validate(input: String, against phrase: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines) == phrase
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add TaskAlarm/Logic/PhraseTask.swift TaskAlarmTests/PhraseTaskTests.swift
git commit -m "feat: phrase task generation and exact-match validation"
```

---

### Task 4: QRTask logic

**Files:**
- Create: `TaskAlarm/Logic/QRTask.swift`
- Test: `TaskAlarmTests/QRTaskTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// TaskAlarmTests/QRTaskTests.swift
import Testing
@testable import TaskAlarm

struct QRTaskTests {
    @Test func payloadHasWakeupPrefix() {
        let payload = QRTask.generatePayload()
        #expect(payload.hasPrefix("wakeup-"))
    }

    @Test func payloadsAreUnique() {
        #expect(QRTask.generatePayload() != QRTask.generatePayload())
    }

    @Test func validateAcceptsMatchingPayload() {
        let payload = QRTask.generatePayload()
        #expect(QRTask.validate(scanned: payload, against: payload))
    }

    @Test func validateRejectsOtherPayload() {
        #expect(!QRTask.validate(scanned: "wakeup-aaaa", against: "wakeup-bbbb"))
    }

    @Test func validateRejectsArbitraryQRContent() {
        #expect(!QRTask.validate(scanned: "https://example.com", against: QRTask.generatePayload()))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20`
Expected: FAIL — `cannot find 'QRTask' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// TaskAlarm/Logic/QRTask.swift
import Foundation

enum QRTask {
    static func generatePayload() -> String {
        "wakeup-\(UUID().uuidString)"
    }

    static func validate(scanned: String, against payload: String) -> Bool {
        scanned == payload
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add TaskAlarm/Logic/QRTask.swift TaskAlarmTests/QRTaskTests.swift
git commit -m "feat: QR payload generation and validation"
```

---

### Task 5: GuardPolicy and SnoozePolicy

**Files:**
- Create: `TaskAlarm/Logic/GuardPolicy.swift`
- Create: `TaskAlarm/Logic/SnoozePolicy.swift`
- Test: `TaskAlarmTests/GuardPolicyTests.swift`
- Test: `TaskAlarmTests/SnoozePolicyTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// TaskAlarmTests/GuardPolicyTests.swift
import Testing
@testable import TaskAlarm

struct GuardPolicyTests {
    @Test func reArmsBelowCap() {
        #expect(GuardPolicy.action(forGuardCount: 0) == .reArm(after: 90))
        #expect(GuardPolicy.action(forGuardCount: 19) == .reArm(after: 90))
    }

    @Test func givesUpAtCap() {
        #expect(GuardPolicy.action(forGuardCount: 20) == .giveUp)
        #expect(GuardPolicy.action(forGuardCount: 25) == .giveUp)
    }
}
```

```swift
// TaskAlarmTests/SnoozePolicyTests.swift
import Testing
@testable import TaskAlarm

struct SnoozePolicyTests {
    @Test func allowsUpToThreeSnoozes() {
        #expect(SnoozePolicy.canSnooze(snoozesUsed: 0))
        #expect(SnoozePolicy.canSnooze(snoozesUsed: 2))
        #expect(!SnoozePolicy.canSnooze(snoozesUsed: 3))
    }

    @Test func snoozeDurationIsNineMinutes() {
        #expect(SnoozePolicy.duration == 9 * 60)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20`
Expected: FAIL — `cannot find 'GuardPolicy' in scope`

- [ ] **Step 3: Write the implementations**

```swift
// TaskAlarm/Logic/GuardPolicy.swift
import Foundation

enum GuardPolicy {
    enum Action: Equatable {
        case reArm(after: TimeInterval)
        case giveUp
    }

    static let interval: TimeInterval = 90
    static let maxGuards = 20

    static func action(forGuardCount count: Int) -> Action {
        count >= maxGuards ? .giveUp : .reArm(after: interval)
    }
}
```

```swift
// TaskAlarm/Logic/SnoozePolicy.swift
import Foundation

enum SnoozePolicy {
    static let duration: TimeInterval = 9 * 60
    static let maxSnoozes = 3

    static func canSnooze(snoozesUsed: Int) -> Bool {
        snoozesUsed < maxSnoozes
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add TaskAlarm/Logic/GuardPolicy.swift TaskAlarm/Logic/SnoozePolicy.swift TaskAlarmTests/GuardPolicyTests.swift TaskAlarmTests/SnoozePolicyTests.swift
git commit -m "feat: guard re-arm policy (90s, cap 20) and snooze policy (9min, max 3)"
```

---

### Task 6: AlarmScheduling protocol + AlarmKit wrapper

AlarmKit calls only run meaningfully on a device; the wrapper is thin and untested, everything above it uses the protocol.

**Files:**
- Create: `TaskAlarm/Scheduling/AlarmScheduling.swift`
- Create: `TaskAlarm/Scheduling/AlarmKitScheduler.swift`

- [ ] **Step 1: Define the protocol**

```swift
// TaskAlarm/Scheduling/AlarmScheduling.swift
import Foundation

protocol AlarmScheduling: Sendable {
    /// Returns true if alarm authorization is granted.
    func requestAuthorization() async -> Bool
    /// Schedules the main alarm for an AlarmItem. Returns the AlarmKit alarm ID.
    func scheduleAlarm(for item: AlarmItemSnapshot) async throws -> UUID
    /// Schedules a one-shot alarm (guard or snooze) after `interval` seconds. Returns its ID.
    func scheduleOneShot(label: String, after interval: TimeInterval,
                         originalAlarmID: UUID) async throws -> UUID
    /// Stops a currently ringing alarm.
    func stop(id: UUID) throws
    /// Cancels a scheduled (not yet fired) alarm.
    func cancel(id: UUID) throws
}

/// Plain value passed across actor boundaries (SwiftData models are not Sendable).
struct AlarmItemSnapshot: Sendable {
    let id: UUID
    let hour: Int
    let minute: Int
    let weekdays: [Int]   // 1 = Sunday … 7 = Saturday
    let label: String
}
```

- [ ] **Step 2: Write the AlarmKit implementation**

```swift
// TaskAlarm/Scheduling/AlarmKitScheduler.swift
import AlarmKit
import AppIntents
import SwiftUI

struct TaskAlarmMetadata: AlarmMetadata {
    let originalAlarmID: UUID
}

final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()
    private let manager = AlarmManager.shared

    func requestAuthorization() async -> Bool {
        do {
            return try await manager.requestAuthorization() == .authorized
        } catch {
            return false
        }
    }

    func scheduleAlarm(for item: AlarmItemSnapshot) async throws -> UUID {
        let time = Alarm.Schedule.Relative.Time(hour: item.hour, minute: item.minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence =
            item.weekdays.isEmpty ? .never : .weekly(item.weekdays.compactMap(Self.localeWeekday))
        let schedule = Alarm.Schedule.relative(.init(time: time, repeats: recurrence))
        return try await schedule(schedule: schedule, label: item.label, originalAlarmID: item.id)
    }

    func scheduleOneShot(label: String, after interval: TimeInterval,
                         originalAlarmID: UUID) async throws -> UUID {
        let schedule = Alarm.Schedule.fixed(Date.now.addingTimeInterval(interval))
        return try await schedule(schedule: schedule, label: label, originalAlarmID: originalAlarmID)
    }

    private func schedule(schedule: Alarm.Schedule, label: String,
                          originalAlarmID: UUID) async throws -> UUID {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: label.isEmpty ? "Wake up!" : label),
            secondaryButton: AlarmButton(text: "Solve task", textColor: .white,
                                         systemImageName: "qrcode.viewfinder"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: TaskAlarmMetadata(originalAlarmID: originalAlarmID),
            tintColor: Color.orange)
        let id = UUID()
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopWithoutTaskIntent(originalAlarmID: originalAlarmID.uuidString),
            secondaryIntent: OpenTaskGateIntent(originalAlarmID: originalAlarmID.uuidString))
        _ = try await manager.schedule(id: id, configuration: configuration)
        return id
    }

    func stop(id: UUID) throws { try manager.stop(id: id) }
    func cancel(id: UUID) throws { try manager.cancel(id: id) }

    /// Maps Calendar weekday number (1 = Sunday) to Locale.Weekday.
    static func localeWeekday(_ number: Int) -> Locale.Weekday? {
        switch number {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}
```

Note: exact signatures of `AlarmPresentation.Alert` / `AlarmManager.AlarmConfiguration.alarm` may differ slightly by Xcode SDK minor version (one `Alert` initializer was deprecated in 26.0–26.1). If the build errors, fix against the autocomplete signature — the structure (alert + attributes + stopIntent + secondaryIntent) is correct per Apple docs.

This file won't compile until the intents exist — Task 7 follows immediately; build at the end of Task 7.

- [ ] **Step 3: Commit (with Task 7)** — see Task 7 Step 4.

---

### Task 7: App Intents (cheat detection + open gate)

**Files:**
- Create: `TaskAlarm/Intents/OpenTaskGateIntent.swift`
- Create: `TaskAlarm/Intents/StopWithoutTaskIntent.swift`
- Create: `TaskAlarm/AppRouter.swift`
- Create: `TaskAlarm/GateService.swift`

The gate logic lives in `GateService` (intents stay thin). `GateService` is constructed with any `AlarmScheduling` — the AlarmKit singleton in production.

- [ ] **Step 1: Write AppRouter**

```swift
// TaskAlarm/AppRouter.swift
import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    /// When set, the UI must present the task gate for this AlarmItem id.
    var activeGateAlarmID: UUID?
}
```

- [ ] **Step 2: Write GateService**

```swift
// TaskAlarm/GateService.swift
import Foundation
import SwiftData

/// Coordinates pending-task state and guard alarms. Called from intents and views.
@MainActor
final class GateService {
    static var shared = GateService(scheduler: AlarmKitScheduler.shared)

    let scheduler: any AlarmScheduling
    var modelContext: ModelContext?   // injected at app launch

    init(scheduler: any AlarmScheduling) {
        self.scheduler = scheduler
    }

    private func pendingState(for alarmID: UUID) throws -> PendingTaskState? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<PendingTaskState>(
            predicate: #Predicate { $0.alarmID == alarmID })
        return try context.fetch(descriptor).first
    }

    /// Stop pressed without task: record cheat, schedule guard alarm per policy.
    func handleCheatStop(originalAlarmID: UUID) async {
        guard let context = modelContext else { return }
        do {
            let pending = try pendingState(for: originalAlarmID)
                ?? {
                    let p = PendingTaskState(alarmID: originalAlarmID, firedAt: .now)
                    context.insert(p)
                    return p
                }()
            switch GuardPolicy.action(forGuardCount: pending.guardCount) {
            case .reArm(let interval):
                pending.guardCount += 1
                pending.guardAlarmKitID = try await scheduler.scheduleOneShot(
                    label: "No escape — solve the task",
                    after: interval,
                    originalAlarmID: originalAlarmID)
            case .giveUp:
                context.delete(pending)   // marked missed; alarm gives up
            }
            try context.save()
        } catch {
            // Persistence/scheduling failure: nothing more we can do from an intent.
        }
    }

    /// Secondary button pressed: open gate, also arm a guard in case user ignores the task.
    func handleOpenGate(originalAlarmID: UUID) async {
        AppRouter.shared.activeGateAlarmID = originalAlarmID
        await handleCheatStop(originalAlarmID: originalAlarmID)
    }

    /// Task completed: cancel guard chain, stop any ringing alarm, clear state.
    /// Returns snoozes used so far (for PostTaskView).
    func completeTask(originalAlarmID: UUID) -> Int {
        guard let context = modelContext else { return 0 }
        var snoozesUsed = 0
        do {
            if let pending = try pendingState(for: originalAlarmID) {
                snoozesUsed = pending.snoozesUsed
                if let guardID = pending.guardAlarmKitID {
                    try? scheduler.cancel(id: guardID)
                }
                context.delete(pending)
                try context.save()
            }
            // Stop the original ringing alarm if still active.
            let descriptor = FetchDescriptor<AlarmItem>(
                predicate: #Predicate { $0.id == originalAlarmID })
            if let item = try context.fetch(descriptor).first,
               let kitID = item.alarmKitID {
                try? scheduler.stop(id: kitID)
            }
        } catch {}
        return snoozesUsed
    }

    /// Snooze after task: schedule one-shot, re-create pending state with incremented snooze count.
    func snooze(originalAlarmID: UUID, snoozesUsed: Int) async {
        guard let context = modelContext else { return }
        do {
            let pending = PendingTaskState(alarmID: originalAlarmID, firedAt: .now,
                                           snoozesUsed: snoozesUsed + 1)
            pending.guardAlarmKitID = try await scheduler.scheduleOneShot(
                label: "Snooze over",
                after: SnoozePolicy.duration,
                originalAlarmID: originalAlarmID)
            context.insert(pending)
            try context.save()
        } catch {}
    }
}
```

- [ ] **Step 3: Write the intents**

```swift
// TaskAlarm/Intents/StopWithoutTaskIntent.swift
import AppIntents

struct StopWithoutTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var originalAlarmID: String

    init() {}
    init(originalAlarmID: String) {
        self.originalAlarmID = originalAlarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: originalAlarmID) {
            await GateService.shared.handleCheatStop(originalAlarmID: id)
        }
        return .result()
    }
}
```

```swift
// TaskAlarm/Intents/OpenTaskGateIntent.swift
import AppIntents

struct OpenTaskGateIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Solve Task"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    var originalAlarmID: String

    init() {}
    init(originalAlarmID: String) {
        self.originalAlarmID = originalAlarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: originalAlarmID) {
            await GateService.shared.handleOpenGate(originalAlarmID: id)
        }
        return .result()
    }
}
```

- [ ] **Step 4: Build, then commit**

Run: `xcodebuild -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`. (If AlarmKit signatures drifted, fix per autocomplete — see Task 6 note.)

```bash
git add TaskAlarm/Scheduling TaskAlarm/Intents TaskAlarm/AppRouter.swift TaskAlarm/GateService.swift
git commit -m "feat: AlarmKit scheduler, gate service, stop/open intents with guard re-arm"
```

---

### Task 8: GateService unit tests with mock scheduler

**Files:**
- Test: `TaskAlarmTests/GateServiceTests.swift`

- [ ] **Step 1: Write the tests (mock scheduler included)**

```swift
// TaskAlarmTests/GateServiceTests.swift
import Testing
import SwiftData
@testable import TaskAlarm

final class MockScheduler: AlarmScheduling, @unchecked Sendable {
    var scheduledOneShots: [(label: String, interval: TimeInterval, originalAlarmID: UUID)] = []
    var cancelledIDs: [UUID] = []
    var stoppedIDs: [UUID] = []

    func requestAuthorization() async -> Bool { true }
    func scheduleAlarm(for item: AlarmItemSnapshot) async throws -> UUID { UUID() }
    func scheduleOneShot(label: String, after interval: TimeInterval,
                         originalAlarmID: UUID) async throws -> UUID {
        scheduledOneShots.append((label, interval, originalAlarmID))
        return UUID()
    }
    func stop(id: UUID) throws { stoppedIDs.append(id) }
    func cancel(id: UUID) throws { cancelledIDs.append(id) }
}

@MainActor
struct GateServiceTests {
    func makeService() throws -> (GateService, MockScheduler, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AlarmItem.self, QRCodeRecord.self, PendingTaskState.self,
            configurations: config)
        let mock = MockScheduler()
        let service = GateService(scheduler: mock)
        service.modelContext = container.mainContext
        return (service, mock, container.mainContext)
    }

    @Test func cheatStopSchedulesGuardAndIncrementsCount() async throws {
        let (service, mock, context) = try makeService()
        let alarmID = UUID()

        await service.handleCheatStop(originalAlarmID: alarmID)

        #expect(mock.scheduledOneShots.count == 1)
        #expect(mock.scheduledOneShots[0].interval == 90)
        let pending = try context.fetch(FetchDescriptor<PendingTaskState>())
        #expect(pending.count == 1)
        #expect(pending[0].guardCount == 1)
    }

    @Test func cheatStopGivesUpAtCap() async throws {
        let (service, mock, context) = try makeService()
        let alarmID = UUID()
        let pending = PendingTaskState(alarmID: alarmID, firedAt: .now,
                                       guardCount: GuardPolicy.maxGuards)
        context.insert(pending)
        try context.save()

        await service.handleCheatStop(originalAlarmID: alarmID)

        #expect(mock.scheduledOneShots.isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingTaskState>()).isEmpty)
    }

    @Test func completeTaskCancelsGuardAndClearsState() async throws {
        let (service, mock, context) = try makeService()
        let alarmID = UUID()
        await service.handleCheatStop(originalAlarmID: alarmID)

        _ = service.completeTask(originalAlarmID: alarmID)

        #expect(mock.cancelledIDs.count == 1)
        #expect(try context.fetch(FetchDescriptor<PendingTaskState>()).isEmpty)
    }

    @Test func snoozeSchedulesNineMinuteOneShot() async throws {
        let (service, mock, context) = try makeService()
        let alarmID = UUID()

        await service.snooze(originalAlarmID: alarmID, snoozesUsed: 0)

        #expect(mock.scheduledOneShots.count == 1)
        #expect(mock.scheduledOneShots[0].interval == SnoozePolicy.duration)
        let pending = try context.fetch(FetchDescriptor<PendingTaskState>())
        #expect(pending[0].snoozesUsed == 1)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`. If a test fails, fix `GateService` (not the test) until green.

- [ ] **Step 3: Commit**

```bash
git add TaskAlarmTests/GateServiceTests.swift
git commit -m "test: GateService guard loop, give-up cap, completion, snooze"
```

---

### Task 9: Alarm list and edit views

**Files:**
- Create: `TaskAlarm/Views/AlarmListView.swift`
- Create: `TaskAlarm/Views/AlarmEditView.swift`
- Modify: `TaskAlarm/ContentView.swift` (replace placeholder)

UI tasks: build-verify + manual check in simulator; logic already tested.

- [ ] **Step 1: Write AlarmListView**

```swift
// TaskAlarm/Views/AlarmListView.swift
import SwiftUI
import SwiftData

struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlarmItem.hour) private var alarms: [AlarmItem]
    @State private var editingAlarm: AlarmItem?
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(alarms) { alarm in
                    AlarmRow(alarm: alarm)
                        .contentShape(Rectangle())
                        .onTapGesture { editingAlarm = alarm }
                }
                .onDelete(perform: deleteAlarms)
            }
            .navigationTitle("TaskAlarm")
            .toolbar {
                Button("Add", systemImage: "plus") { showingNew = true }
            }
            .sheet(item: $editingAlarm) { AlarmEditView(alarm: $0) }
            .sheet(isPresented: $showingNew) { AlarmEditView(alarm: nil) }
            .overlay {
                if alarms.isEmpty {
                    ContentUnavailableView("No alarms",
                        systemImage: "alarm",
                        description: Text("Tap + to add one. Good luck silencing it."))
                }
            }
        }
    }

    private func deleteAlarms(at offsets: IndexSet) {
        for index in offsets {
            let alarm = alarms[index]
            if let kitID = alarm.alarmKitID {
                try? GateService.shared.scheduler.cancel(id: kitID)
            }
            modelContext.delete(alarm)
        }
    }
}

struct AlarmRow: View {
    @Bindable var alarm: AlarmItem

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(String(format: "%d:%02d", alarm.hour, alarm.minute))
                    .font(.largeTitle.weight(.light))
                HStack(spacing: 8) {
                    if !alarm.label.isEmpty { Text(alarm.label) }
                    Text(weekdaySummary).foregroundStyle(.secondary)
                    Image(systemName: alarm.taskType == .qrScan ? "qrcode" : "keyboard")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer()
            Toggle("", isOn: $alarm.isEnabled)
                .labelsHidden()
                .onChange(of: alarm.isEnabled) { _, enabled in
                    Task { await AlarmLifecycle.setEnabled(enabled, for: alarm) }
                }
        }
    }

    private var weekdaySummary: String {
        if alarm.weekdays.isEmpty { return "Once" }
        if alarm.weekdays.count == 7 { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols // index 0 = Sunday
        return alarm.weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: " ")
    }
}
```

- [ ] **Step 2: Write AlarmLifecycle helper**

```swift
// Append to TaskAlarm/Views/AlarmListView.swift

/// Schedules/cancels the AlarmKit alarm when an AlarmItem changes.
enum AlarmLifecycle {
    @MainActor
    static func setEnabled(_ enabled: Bool, for alarm: AlarmItem) async {
        let scheduler = GateService.shared.scheduler
        if enabled {
            let snapshot = AlarmItemSnapshot(id: alarm.id, hour: alarm.hour,
                minute: alarm.minute, weekdays: alarm.weekdays, label: alarm.label)
            alarm.alarmKitID = try? await scheduler.scheduleAlarm(for: snapshot)
            if alarm.alarmKitID == nil { alarm.isEnabled = false }
        } else if let kitID = alarm.alarmKitID {
            try? scheduler.cancel(id: kitID)
            alarm.alarmKitID = nil
        }
    }
}
```

- [ ] **Step 3: Write AlarmEditView**

```swift
// TaskAlarm/Views/AlarmEditView.swift
import SwiftUI
import SwiftData

struct AlarmEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existing: AlarmItem?
    @State private var time: Date
    @State private var weekdays: Set<Int>
    @State private var label: String
    @State private var taskType: TaskType
    @State private var showQRSetup = false

    init(alarm: AlarmItem?) {
        self.existing = alarm
        var components = DateComponents()
        components.hour = alarm?.hour ?? 7
        components.minute = alarm?.minute ?? 0
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
        _weekdays = State(initialValue: Set(alarm?.weekdays ?? []))
        _label = State(initialValue: alarm?.label ?? "")
        _taskType = State(initialValue: alarm?.taskType ?? .phrase)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)

                Section("Repeat") {
                    WeekdayPicker(selection: $weekdays)
                }

                Section("Task to dismiss") {
                    Picker("Task", selection: $taskType) {
                        ForEach(TaskType.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section { TextField("Label", text: $label) }
            }
            .navigationTitle(existing == nil ? "New Alarm" : "Edit Alarm")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                }
            }
            .sheet(isPresented: $showQRSetup, onDismiss: { dismiss() }) {
                QRSetupView()
            }
        }
    }

    @MainActor
    private func save() async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let alarm = existing ?? AlarmItem(hour: 0, minute: 0)
        alarm.hour = components.hour ?? 7
        alarm.minute = components.minute ?? 0
        alarm.weekdays = Array(weekdays).sorted()
        alarm.label = label
        alarm.taskType = taskType
        if existing == nil { modelContext.insert(alarm) }

        if let kitID = alarm.alarmKitID {
            try? GateService.shared.scheduler.cancel(id: kitID)
            alarm.alarmKitID = nil
        }
        alarm.isEnabled = true
        await AlarmLifecycle.setEnabled(true, for: alarm)

        if taskType == .qrScan && !QRSetupView.qrExists(in: modelContext) {
            showQRSetup = true   // dismissal of setup sheet dismisses editor
        } else {
            dismiss()
        }
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let symbols = Calendar.current.veryShortWeekdaySymbols // index 0 = Sunday

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Text(symbols[day - 1])
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(isOn ? Color.orange : Color(.systemGray5),
                                in: Circle())
                    .foregroundStyle(isOn ? .white : .primary)
                    .onTapGesture {
                        if isOn { selection.remove(day) } else { selection.insert(day) }
                    }
            }
        }
    }
}
```

- [ ] **Step 4: Replace ContentView**

```swift
// TaskAlarm/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        AlarmListView()
    }
}
```

- [ ] **Step 5: Build (QRSetupView stub needed)**

Add a temporary minimal `QRSetupView` so this task builds standalone (replaced in Task 10):

```swift
// TaskAlarm/Views/QRSetupView.swift  (stub, replaced in Task 10)
import SwiftUI
import SwiftData

struct QRSetupView: View {
    var body: some View { Text("QR setup") }
    static func qrExists(in context: ModelContext) -> Bool {
        ((try? context.fetch(FetchDescriptor<QRCodeRecord>()))?.isEmpty == false)
    }
}
```

Run: `xcodebuild -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Manual simulator check**

Run the app in the iPhone 17 simulator. Verify: add alarm, weekday picker toggles, list row shows time/label/task icon, toggle and delete work. (AlarmKit authorization prompt may appear; simulator alarm firing is unreliable — device tests come later.)

- [ ] **Step 7: Commit**

```bash
git add TaskAlarm/Views TaskAlarm/ContentView.swift
git commit -m "feat: alarm list and edit UI with weekday repeat and task type picker"
```

---

### Task 10: QR setup view (generate + print/share)

**Files:**
- Modify: `TaskAlarm/Views/QRSetupView.swift` (replace stub)

- [ ] **Step 1: Implement QR generation and share**

```swift
// TaskAlarm/Views/QRSetupView.swift
import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

struct QRSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Print this code and stick it far from your bed — bathroom mirror, kitchen, hallway.")
                    .multilineTextAlignment(.center)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)

                    ShareLink(item: Image(uiImage: qrImage),
                              preview: SharePreview("Wake-up QR code",
                                                    image: Image(uiImage: qrImage))) {
                        Label("Share / Print", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Your wake-up code")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: loadOrCreate)
        }
    }

    static func qrExists(in context: ModelContext) -> Bool {
        ((try? context.fetch(FetchDescriptor<QRCodeRecord>()))?.isEmpty == false)
    }

    private func loadOrCreate() {
        let existing = try? modelContext.fetch(FetchDescriptor<QRCodeRecord>()).first
        let record: QRCodeRecord
        if let existing {
            record = existing
        } else {
            record = QRCodeRecord(payload: QRTask.generatePayload())
            modelContext.insert(record)
            try? modelContext.save()
        }
        qrImage = Self.makeQRImage(payload: record.payload)
    }

    static func makeQRImage(payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
```

- [ ] **Step 2: Build and manual check**

Run: `xcodebuild -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

In simulator: create an alarm with QR task → setup sheet appears with a scannable QR image → share sheet opens.

- [ ] **Step 3: Commit**

```bash
git add TaskAlarm/Views/QRSetupView.swift
git commit -m "feat: QR code generation and share/print setup sheet"
```

---

### Task 11: Task gate — phrase view, QR scan view, gate container, post-task view

**Files:**
- Create: `TaskAlarm/Views/PhraseTaskView.swift`
- Create: `TaskAlarm/Views/QRScanView.swift`
- Create: `TaskAlarm/Views/TaskGateView.swift`
- Create: `TaskAlarm/Views/PostTaskView.swift`

- [ ] **Step 1: PhraseTaskView (paste blocked, re-randomize per attempt)**

```swift
// TaskAlarm/Views/PhraseTaskView.swift
import SwiftUI

struct PhraseTaskView: View {
    let onSolved: () -> Void
    @State private var phrase = PhraseTask.generate()
    @State private var input = ""
    @State private var attemptFailed = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Type this exactly:")
                .font(.headline)
            Text(phrase)
                .font(.title3.monospaced())
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .textSelection(.disabled)   // no copy → no paste cheat

            NoPasteTextField(text: $input)
                .frame(height: 44)
                .padding(.horizontal)

            if attemptFailed {
                Text("Wrong — new phrase generated.")
                    .foregroundStyle(.red)
            }

            Button("Check") {
                if PhraseTask.validate(input: input, against: phrase) {
                    onSolved()
                } else {
                    phrase = PhraseTask.generate()
                    input = ""
                    attemptFailed = true
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(input.isEmpty)
        }
        .padding()
    }
}

/// UITextField subclass that rejects paste.
struct NoPasteTextField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> PasteBlockingTextField {
        let field = PasteBlockingTextField()
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.delegate = context.coordinator
        return field
    }

    func updateUIView(_ uiView: PasteBlockingTextField, context: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            let current = (textField.text ?? "") as NSString
            text = current.replacingCharacters(in: range, with: string)
            return true
        }
    }
}

final class PasteBlockingTextField: UITextField {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }
}
```

- [ ] **Step 2: QRScanView (VisionKit scanner)**

```swift
// TaskAlarm/Views/QRScanView.swift
import SwiftUI
import SwiftData
import VisionKit

struct QRScanView: View {
    let expectedPayload: String
    let onSolved: () -> Void
    let onFallbackRequested: () -> Void

    @State private var fallbackAvailable = false
    @State private var wrongCodeScanned = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Scan your wake-up QR code")
                .font(.headline)

            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ScannerRepresentable { scanned in
                    if QRTask.validate(scanned: scanned, against: expectedPayload) {
                        onSolved()
                    } else {
                        wrongCodeScanned = true
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                // Camera unavailable/denied → fall back immediately (spec: no dead end).
                Text("Camera unavailable.")
                    .onAppear { onFallbackRequested() }
            }

            if wrongCodeScanned {
                Text("That's not your code.").foregroundStyle(.red)
            }

            if fallbackAvailable {
                Button("Can't scan? Type a phrase instead") { onFallbackRequested() }
            }
        }
        .padding()
        .task {
            try? await Task.sleep(for: .seconds(120))
            fallbackAvailable = true
        }
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue {
                    onScan(value)
                }
            }
        }
    }
}
```

- [ ] **Step 3: TaskGateView + PostTaskView**

```swift
// TaskAlarm/Views/TaskGateView.swift
import SwiftUI
import SwiftData

struct TaskGateView: View {
    let alarmID: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var solved = false
    @State private var snoozesUsed = 0
    @State private var forcePhraseFallback = false

    var body: some View {
        if solved {
            PostTaskView(alarmID: alarmID, snoozesUsed: snoozesUsed)
        } else {
            content
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var content: some View {
        let alarm = try? modelContext.fetch(
            FetchDescriptor<AlarmItem>(predicate: #Predicate { $0.id == alarmID })).first
        let qrPayload = (try? modelContext.fetch(FetchDescriptor<QRCodeRecord>()).first)?.payload

        if let alarm, alarm.taskType == .qrScan, let qrPayload, !forcePhraseFallback {
            QRScanView(expectedPayload: qrPayload,
                       onSolved: complete,
                       onFallbackRequested: { forcePhraseFallback = true })
        } else {
            PhraseTaskView(onSolved: complete)
        }
    }

    private func complete() {
        snoozesUsed = GateService.shared.completeTask(originalAlarmID: alarmID)
        solved = true
    }
}
```

```swift
// TaskAlarm/Views/PostTaskView.swift
import SwiftUI

struct PostTaskView: View {
    let alarmID: UUID
    let snoozesUsed: Int

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Task done. You're awake.")
                .font(.title2)

            Button("Dismiss alarm") {
                AppRouter.shared.activeGateAlarmID = nil
            }
            .buttonStyle(.borderedProminent)

            if SnoozePolicy.canSnooze(snoozesUsed: snoozesUsed) {
                Button("Snooze 9 minutes (\(SnoozePolicy.maxSnoozes - snoozesUsed) left)") {
                    Task {
                        await GateService.shared.snooze(originalAlarmID: alarmID,
                                                        snoozesUsed: snoozesUsed)
                        AppRouter.shared.activeGateAlarmID = nil
                    }
                }
            }
        }
        .padding()
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add TaskAlarm/Views/PhraseTaskView.swift TaskAlarm/Views/QRScanView.swift TaskAlarm/Views/TaskGateView.swift TaskAlarm/Views/PostTaskView.swift
git commit -m "feat: task gate with QR scan, paste-proof phrase task, 2-min fallback, post-task snooze"
```

---

### Task 12: App entry wiring, authorization gate, pending-state resume

**Files:**
- Modify: `TaskAlarm/TaskAlarmApp.swift`
- Create: `TaskAlarm/Views/AuthorizationBlockedView.swift`

- [ ] **Step 1: AuthorizationBlockedView**

```swift
// TaskAlarm/Views/AuthorizationBlockedView.swift
import SwiftUI

struct AuthorizationBlockedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "alarm.waves.left.and.right")
                .font(.system(size: 56))
            Text("Alarm permission required")
                .font(.title2.bold())
            Text("TaskAlarm cannot ring without alarm permission. Enable it in Settings.")
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
```

- [ ] **Step 2: App entry**

```swift
// TaskAlarm/TaskAlarmApp.swift
import SwiftUI
import SwiftData

@main
struct TaskAlarmApp: App {
    let container: ModelContainer
    @State private var router = AppRouter.shared
    @State private var authorized: Bool? = nil

    init() {
        do {
            container = try ModelContainer(
                for: AlarmItem.self, QRCodeRecord.self, PendingTaskState.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        GateService.shared.modelContext = container.mainContext
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch authorized {
                case nil: ProgressView()
                case false?: AuthorizationBlockedView()
                case true?: ContentView()
                }
            }
            .task {
                authorized = await GateService.shared.scheduler.requestAuthorization()
                resumePendingGate()
            }
            .fullScreenCover(item: Binding(
                get: { router.activeGateAlarmID.map(GateTarget.init) },
                set: { router.activeGateAlarmID = $0?.id })) { target in
                TaskGateView(alarmID: target.id)
            }
        }
        .modelContainer(container)
    }

    /// App relaunched with unfinished gate (force-kill survival).
    private func resumePendingGate() {
        let pending = try? container.mainContext.fetch(FetchDescriptor<PendingTaskState>())
        if let first = pending?.first {
            AppRouter.shared.activeGateAlarmID = first.alarmID
        }
    }
}

struct GateTarget: Identifiable {
    let id: UUID
}
```

- [ ] **Step 3: Build and run full test suite**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add TaskAlarm/TaskAlarmApp.swift TaskAlarm/Views/AuthorizationBlockedView.swift
git commit -m "feat: app wiring — authorization gate, full-screen task gate, pending-state resume"
```

---

### Task 13: One-shot auto-disable + alarmUpdates sync

**Files:**
- Modify: `TaskAlarm/TaskAlarmApp.swift` (add observation task)
- Modify: `TaskAlarm/GateService.swift` (add sync method)

- [ ] **Step 1: Add sync method to GateService**

```swift
// Append inside GateService (TaskAlarm/GateService.swift)

    /// Reconcile with AlarmKit's alarm set: one-shot alarms that no longer exist
    /// in AlarmKit have fired (or were removed) — disable their toggle.
    func syncWithAlarmKit(activeAlarmKitIDs: Set<UUID>) {
        guard let context = modelContext else { return }
        do {
            let items = try context.fetch(FetchDescriptor<AlarmItem>())
            for item in items where item.isEnabled && item.weekdays.isEmpty {
                if let kitID = item.alarmKitID, !activeAlarmKitIDs.contains(kitID) {
                    item.isEnabled = false
                    item.alarmKitID = nil
                }
            }
            try context.save()
        } catch {}
    }
```

- [ ] **Step 2: Observe alarmUpdates in the app**

Add to `TaskAlarmApp` body's `.task` modifier, after `resumePendingGate()`:

```swift
// In TaskAlarmApp.swift, extend the .task closure:
            .task {
                authorized = await GateService.shared.scheduler.requestAuthorization()
                resumePendingGate()
                for await alarms in AlarmManager.shared.alarmUpdates {
                    GateService.shared.syncWithAlarmKit(
                        activeAlarmKitIDs: Set(alarms.map(\.id)))
                }
            }
```

Add `import AlarmKit` at the top of `TaskAlarmApp.swift`.

- [ ] **Step 3: Write the sync test**

```swift
// Append to TaskAlarmTests/GateServiceTests.swift

    @Test func syncDisablesFiredOneShots() async throws {
        let (service, _, context) = try makeService()
        let oneShot = AlarmItem(hour: 7, minute: 0, weekdays: [], label: "Once")
        oneShot.alarmKitID = UUID()
        oneShot.isEnabled = true
        let weekly = AlarmItem(hour: 8, minute: 0, weekdays: [2], label: "Weekly")
        weekly.alarmKitID = UUID()
        weekly.isEnabled = true
        context.insert(oneShot)
        context.insert(weekly)
        try context.save()

        // Neither ID present in AlarmKit's set anymore.
        service.syncWithAlarmKit(activeAlarmKitIDs: [])

        #expect(oneShot.isEnabled == false)   // one-shot fired → disabled
        #expect(weekly.isEnabled == true)     // weekly stays enabled (AlarmKit reschedules)
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project TaskAlarm.xcodeproj -scheme TaskAlarm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add TaskAlarm/GateService.swift TaskAlarm/TaskAlarmApp.swift TaskAlarmTests/GateServiceTests.swift
git commit -m "feat: alarmUpdates sync — auto-disable fired one-shot alarms"
```

---

### Task 14: Manual device test matrix

Real device required (AlarmKit alert behavior, silent switch, camera). iPhone on iOS 26+, developer mode on, app installed via Xcode.

- [ ] **Step 1: Basic ring** — set one-shot alarm 2 min ahead, lock phone. Expect: full-screen system alert with "Solve task" + Stop at fire time.
- [ ] **Step 2: Silent mode** — repeat with silent switch on. Expect: still rings audibly.
- [ ] **Step 3: App killed** — set alarm, force-quit app, lock. Expect: still rings; tapping "Solve task" relaunches into gate.
- [ ] **Step 4: Cheat stop** — when ringing, press Stop. Expect: ~90 s later it rings again. Press Stop again — rings again. Then solve the task; expect quiet.
- [ ] **Step 5: Phrase gate** — phrase alarm: wrong input regenerates phrase; paste unavailable; correct input → PostTaskView.
- [ ] **Step 6: QR gate** — QR alarm: print/display code on another screen; scanning random QR rejected; correct QR → PostTaskView. Wait 2 min without scanning → fallback button appears.
- [ ] **Step 7: Snooze** — solve task → Snooze 9 min. Expect re-ring in 9 min, gate again, snooze counter decremented; after 3 snoozes the button disappears.
- [ ] **Step 8: Reboot** — set alarm 5 min ahead, reboot phone, leave locked. Expect: alarm rings.
- [ ] **Step 9: Record results** — note failures in `docs/superpowers/specs/2026-06-10-alarm-app-design.md` under a new "Device Test Results" section; file fixes as new tasks.

- [ ] **Step 10: Commit**

```bash
git add docs/
git commit -m "docs: device test results"
```

---

## Self-Review Notes

- **Spec coverage:** models (Task 2), tasks/validation (3, 4), guard + snooze policies (5), AlarmKit wrapper + intents (6, 7), gate service incl. cheat loop, give-up cap, completion, snooze (7, 8), alarm CRUD UI (9), QR setup (10), gate UI + fallback + paste-block (11), authorization gate + force-kill resume (12), one-shot auto-disable via alarmUpdates (13), device matrix incl. silent mode/reboot/cheat (14). QR regeneration in settings: deferred — v1 ships without it; re-running setup is possible by deleting the app's data. Acceptable YAGNI cut; noted here deliberately.
- **Known risk:** AlarmKit API signatures (esp. `AlarmPresentation.Alert` init, `AlarmConfiguration.alarm(...)` factory) drifted across 26.0→26.1; Task 6/7 carry an explicit fix-by-autocomplete note. Behavior contract per Apple docs is stable.
- **Type consistency check:** `AlarmItemSnapshot` fields match `AlarmItem`; `GateService.completeTask` returns `Int` consumed by `TaskGateView.complete()`; `scheduleOneShot` label/interval/originalAlarmID consistent across mock and impl; weekday convention (1 = Sunday) consistent in model docs, `localeWeekday`, and both pickers.
