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
                // Background
                Color.gray50
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        if selectedImage == nil {
                            // State 1: Empty State
                            emptyStateView
                        } else {
                            // State 2: Preview State
                            previewStateView
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
                            .foregroundColor(.gray900)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Upload Receipt")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.gray900)
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
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 0) {
            // Hero Section
            VStack(spacing: 12) {
                // Upload Icon
                ZStack {
                    Circle()
                        .fill(Color.blue100)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue600)
                }
                .padding(.bottom, 12)
                
                // Title
                Text("Add Receipt Photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.gray900)
                    .padding(.bottom, 4)
                
                // Description
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
                Button(action: {
                    showCamera = true
                }) {
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
                Button(action: {
                    showPhotoPicker = true
                }) {
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
            
            // Tips Section
            tipsSection
                .padding(.top, 32)
        }
    }
    
    // MARK: - Preview State View
    
    private var previewStateView: some View {
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
                Button(action: {
                    withAnimation {
                        selectedImage = nil
                    }
                }) {
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
                Button(action: handleUpload) {
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
                Button(action: {
                    showPhotoPicker = true
                }) {
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
    
    // MARK: - Tips Section
    
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips for best results:")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.blue900)
            
            VStack(alignment: .leading, spacing: 8) {
                TipRow(text: "Ensure receipt is flat and well-lit")
                TipRow(text: "Capture all items and prices")
                TipRow(text: "Avoid shadows and reflections")
            }
        }
        .frame(maxWidth: 448, alignment: .leading)
        .padding(20)
        .background(Color.blue50)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue100, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    // MARK: - Actions
    
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
                    errorMessage = "Failed to upload receipt: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Tip Row

struct TipRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.blue800)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.blue800)
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
            
            result.item.loadObject(ofClass: UIImage.self) { image, error in
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
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
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
