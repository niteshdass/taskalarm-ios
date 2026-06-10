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
}
