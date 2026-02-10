import SwiftUI

/// Full-screen sheet for previewing the receipt image
struct ReceiptPreviewSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale *= delta
                                    scale = min(max(scale, 1.0), 4.0) // Limit zoom between 1x and 4x
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                }
                        )
                }
                .background(Color.black)
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if scale > 1.0 {
                        Button("Reset Zoom") {
                            withAnimation {
                                scale = 1.0
                            }
                        }
                        .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
        }
    }
}

// MARK: - Preview
struct ReceiptPreviewSheet_Previews: PreviewProvider {
    static var previews: some View {
        ReceiptPreviewSheet(image: UIImage(systemName: "doc.text.image")!)
    }
}
