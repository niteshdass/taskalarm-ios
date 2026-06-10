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
