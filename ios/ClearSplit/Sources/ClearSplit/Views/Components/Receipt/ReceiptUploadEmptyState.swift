import SwiftUI

struct ReceiptUploadEmptyState: View {
    var onTakePhoto: () -> Void
    var onChooseFromGallery: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Hero Section
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue100)
                        .frame(width: 80, height: 80)

                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue600)
                }
                .padding(.bottom, 12)

                Text("Add Receipt Photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.gray900)
                    .padding(.bottom, 4)

                Text("Take a photo or select one from your gallery to add items automatically")
                    .font(.system(size: 14))
                    .foregroundColor(.gray600)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.bottom, 32)
            }
            .padding(.top, 40)

            // Action Buttons
            VStack(spacing: 16) {
                // Primary Button: Take Photo
                Button(action: onTakePhoto) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)

                        Text("Take Photo")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: 448)
                    .frame(height: 96)
                    .background(Color.blue600)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())

                // Secondary Button: Choose from Gallery
                Button(action: onChooseFromGallery) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundColor(.gray900)

                        Text("Choose from Gallery")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.gray900)
                    }
                    .frame(maxWidth: 448)
                    .frame(height: 96)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray300, lineWidth: 2)
                    )
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 32)

            ReceiptUploadTips()
                .padding(.top, 32)
        }
    }
}
