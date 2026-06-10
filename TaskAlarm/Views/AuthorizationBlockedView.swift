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
