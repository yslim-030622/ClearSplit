import SwiftUI

struct ExtractedItemsEmptyState: View {
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Items Found")
                .font(.headline)

            Text("The OCR couldn't extract any items from this receipt. You can add items manually.")
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
