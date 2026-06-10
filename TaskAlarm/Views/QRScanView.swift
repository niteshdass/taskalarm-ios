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
