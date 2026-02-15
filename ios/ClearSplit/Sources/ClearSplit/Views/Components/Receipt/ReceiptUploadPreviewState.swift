import SwiftUI

struct ReceiptUploadPreviewState: View {
    let selectedImage: UIImage?
    let isUploading: Bool
    var onUsePhoto: () -> Void
    var onChooseDifferent: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(spacing: ClearSplitTheme.Spacing.md) {
            // Image Preview Container
            ZStack(alignment: .topTrailing) {
                // Background
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg)
                    .fill(Color.textPrimary)
                    .frame(minHeight: 400, maxHeight: 600)
                    .frame(maxWidth: .infinity)

                // Image
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(minHeight: 400, maxHeight: 600)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(ClearSplitTheme.Radius.lg)
                        .clipped()
                }

                // Remove Button (X)
                Button(action: onRemove) {
                    ZStack {
                        Circle()
                            .fill(Color.textPrimary.opacity(0.8))
                            .frame(width: 40, height: 40)

                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(16)
            }

            // Action Buttons
            VStack(spacing: ClearSplitTheme.Spacing.sm) {
                // Primary Button: Use This Photo
                Button(action: onUsePhoto) {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 20, height: 20)

                            Text("Processing...")
                                .font(ClearSplitTheme.Typography.bodyStrong)
                                .foregroundColor(.textOnBrand)
                        } else {
                            Text("Use This Photo")
                                .font(ClearSplitTheme.Typography.bodyStrong)
                                .foregroundColor(.textOnBrand)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isUploading ? Color.blue400 : Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
                }
                .disabled(isUploading)
                .buttonStyle(PlainButtonStyle())

                // Secondary Button: Choose Different Photo
                Button(action: onChooseDifferent) {
                    Text("Choose Different Photo")
                        .font(ClearSplitTheme.Typography.bodyStrong)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isUploading ? Color.gray100 : Color.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                                .stroke(Color.borderMedium, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
                }
                .disabled(isUploading)
                .buttonStyle(PlainButtonStyle())
            }

            // Info Text
            Text("We'll automatically extract items and prices from your receipt")
                .font(ClearSplitTheme.Typography.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
        }
    }
}
