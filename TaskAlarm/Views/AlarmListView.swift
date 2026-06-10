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
