import SwiftUI

struct ReceiptUploadPreviewState: View {
    let selectedImage: UIImage?
    let isUploading: Bool
    var onUsePhoto: () -> Void
    var onChooseDifferent: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Image Preview Container
            ZStack(alignment: .topTrailing) {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray900)
                    .frame(minHeight: 400, maxHeight: 600)
                    .frame(maxWidth: .infinity)

                // Image
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(minHeight: 400, maxHeight: 600)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(16)
                        .clipped()
                }

                // Remove Button (X)
                Button(action: onRemove) {
                    ZStack {
                        Circle()
                            .fill(Color.gray900.opacity(0.8))
                            .frame(width: 40, height: 40)

                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(16)
            }

            // Action Buttons
            VStack(spacing: 12) {
                // Primary Button: Use This Photo
                Button(action: onUsePhoto) {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 20, height: 20)

                            Text("Processing...")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white)
                        } else {
                            Text("Use This Photo")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isUploading ? Color.blue400 : Color.blue600)
                    .cornerRadius(12)
                }
                .disabled(isUploading)
                .buttonStyle(PlainButtonStyle())

                // Secondary Button: Choose Different Photo
                Button(action: onChooseDifferent) {
                    Text("Choose Different Photo")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.gray900)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isUploading ? Color.gray100 : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray300, lineWidth: 1)
                        )
                        .cornerRadius(12)
                }
                .disabled(isUploading)
                .buttonStyle(PlainButtonStyle())
            }

            // Info Text
            Text("We'll automatically extract items and prices from your receipt")
                .font(.system(size: 14))
                .foregroundColor(.gray600)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
        }
    }
}
