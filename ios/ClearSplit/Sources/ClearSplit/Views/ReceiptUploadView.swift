import SwiftUI
import PhotosUI

struct ReceiptUploadView: View {
    let sessionId: UUID
    let appState: AppState
    let onUploadComplete: (ReceiptUpload) -> Void
    let onBack: () -> Void

    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var errorMessage: String?
    @State private var showError = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        if selectedImage == nil {
                            ReceiptUploadEmptyState(
                                onTakePhoto: { showCamera = true },
                                onChooseFromGallery: { showPhotoPicker = true }
                            )
                        } else {
                            ReceiptUploadPreviewState(
                                selectedImage: selectedImage,
                                isUploading: isUploading,
                                onUsePhoto: handleUpload,
                                onChooseDifferent: { showPhotoPicker = true },
                                onRemove: {
                                    withAnimation {
                                        selectedImage = nil
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 80)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Upload Receipt")
                        .font(ClearSplitTheme.Typography.sectionTitle)
                        .foregroundColor(.textPrimary)
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(selectedImage: $selectedImage)
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePicker(
                    sourceType: .camera,
                    selectedImage: $selectedImage
                )
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }

    private func handleUpload() {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to process image"
            showError = true
            return
        }

        isUploading = true

        Task {
            do {
                let receipt = try await appState.shoppingService.uploadReceipt(
                    sessionId: sessionId,
                    imageData: imageData,
                    contentType: "image/jpeg"
                )

                await MainActor.run {
                    isUploading = false
                    onUploadComplete(receipt)
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .server(_, let message):
                            errorMessage = message ?? "Failed to upload receipt."
                        case .unauthorized:
                            errorMessage = "You are not authorized to upload a receipt for this session."
                        default:
                            errorMessage = "Failed to upload receipt."
                        }
                    } else {
                        errorMessage = "Failed to upload receipt: \(error.localizedDescription)"
                    }
                    showError = true
                }
            }
        }
    }
}

// MARK: - Photo Picker (iOS 14+)

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else { return }

            result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                if let image = image as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image
                    }
                }
            }
        }
    }
}

// MARK: - Image Picker (Camera)

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.selectedImage = image
                }
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
