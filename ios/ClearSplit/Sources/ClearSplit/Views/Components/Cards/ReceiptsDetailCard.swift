import SwiftUI

struct ReceiptsDetailCard: View {
    let receipts: [ReceiptUpload]
    let appState: AppState
    let canUpload: Bool
    let editableReceiptIds: Set<UUID>
    let onDeleteTap: (ReceiptUpload) -> Void
    let onUploadTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.md) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.textSecondary)

                    Text("Receipts")
                        .font(ClearSplitTheme.Typography.sectionTitle)
                        .foregroundColor(.textPrimary)
                }

                Spacer()

                if canUpload {
                    Button(action: onUploadTap) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.brandPrimary)
                            .frame(width: 44, height: 44)
                            .background(Color.brandSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Receipt Content
            if receipts.isEmpty {
                // Empty State
                SwiftUI.Group {
                    if canUpload {
                        Button(action: {
                            onUploadTap()
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.cardInset)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                            .foregroundColor(.borderMedium)
                                    )

                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.textMuted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.cardInset)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                        .foregroundColor(.borderMedium)
                                )

                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.textMuted)
                        }
                    }
                }
            } else {
                // Receipt Thumbnails
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(receipts) { receipt in
                            ReceiptThumbnailView(
                                receipt: receipt,
                                appState: appState,
                                canDelete: editableReceiptIds.contains(receipt.id),
                                onDeleteTap: onDeleteTap
                            )
                        }
                    }
                }
            }
        }
        .padding(ClearSplitTheme.Spacing.lg)
        .sectionStyle()
    }
}
