import SwiftUI

struct ExtractedItemsErrorState: View {
    let message: String
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Extraction Failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Close") {
                onClose()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
