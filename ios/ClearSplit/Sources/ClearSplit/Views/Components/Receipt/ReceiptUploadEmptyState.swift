import SwiftUI

struct ReceiptUploadEmptyState: View {
    var onTakePhoto: () -> Void
    var onChooseFromGallery: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Hero Section
            VStack(spacing: ClearSplitTheme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.brandSurface)
                        .frame(width: 80, height: 80)

                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.brandPrimary)
                }
                .padding(.bottom, 12)

                Text("Add Receipt Photo")
                    .font(ClearSplitTheme.Typography.title)
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 4)

                Text("Take a photo or select one from your gallery to add items automatically")
                    .font(ClearSplitTheme.Typography.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.bottom, 32)
            }
            .padding(.top, 40)

            // Action Buttons
            VStack(spacing: ClearSplitTheme.Spacing.md) {
                // Primary Button: Take Photo
                Button(action: onTakePhoto) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundColor(.textOnBrand)

                        Text("Take Photo")
                            .font(ClearSplitTheme.Typography.sectionTitle)
                            .foregroundColor(.textOnBrand)
                    }
                    .frame(maxWidth: 448)
                    .frame(height: 96)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
                    .applyElevation(.low)
                }
                .buttonStyle(PlainButtonStyle())

                // Secondary Button: Choose from Gallery
                Button(action: onChooseFromGallery) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .foregroundColor(.textPrimary)

                        Text("Choose from Gallery")
                            .font(ClearSplitTheme.Typography.sectionTitle)
                            .foregroundColor(.textPrimary)
                    }
                    .frame(maxWidth: 448)
                    .frame(height: 96)
                    .background(Color.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg)
                            .stroke(Color.borderMedium, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
                    .applyElevation(.low)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 32)

            ReceiptUploadTips()
                .padding(.top, 32)
        }
    }
}
