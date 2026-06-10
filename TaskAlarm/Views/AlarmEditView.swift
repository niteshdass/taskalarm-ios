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
