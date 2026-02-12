import SwiftUI

struct ReceiptUploadTips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips for Best Results")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.gray900)

            VStack(alignment: .leading, spacing: 8) {
                TipRow(number: 1, text: "Use good lighting")
                TipRow(number: 2, text: "Keep the receipt flat and straight")
                TipRow(number: 3, text: "Ensure all items are visible in the photo")
                TipRow(number: 4, text: "Include the total amount at the bottom")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue50)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
    }
}

struct TipRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number).")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue600)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.gray700)

            Spacer()
        }
    }
}
