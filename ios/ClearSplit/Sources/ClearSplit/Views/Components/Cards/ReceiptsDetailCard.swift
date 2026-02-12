import SwiftUI

struct ReceiptsDetailCard: View {
    let receipts: [ReceiptUpload]
    let appState: AppState
    let canDelete: Bool
    let onDeleteTap: (ReceiptUpload) -> Void
    let onUploadTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray700)

                    Text("Receipts")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.gray900)
                }

                Spacer()

                // Camera Button in card (backup to toolbar button)
                Button(action: onUploadTap) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue600)
                        .frame(width: 44, height: 44)
                        .background(Color.blue50)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Receipt Content
            if receipts.isEmpty {
                // Empty State
                Button(action: {
                    onUploadTap()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray100)
                            .frame(width: 80, height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                    .foregroundColor(.gray300)
                            )

                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray400)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // Receipt Thumbnails
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(receipts) { receipt in
                            ReceiptThumbnailView(
                                receipt: receipt,
                                appState: appState,
                                canDelete: canDelete,
                                onDeleteTap: onDeleteTap
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}
