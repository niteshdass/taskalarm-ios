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
