import SwiftUI

struct ReceiptUploadTips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.sm) {
            Text("Tips for Best Results")
                .font(ClearSplitTheme.Typography.bodyStrong)
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                TipRow(number: 1, text: "Use good lighting")
                TipRow(number: 2, text: "Keep the receipt flat and straight")
                TipRow(number: 3, text: "Ensure all items are visible in the photo")
                TipRow(number: 4, text: "Include the total amount at the bottom")
            }
        }
        .padding(ClearSplitTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.infoSurface)
        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                .stroke(Color.infoBorder, lineWidth: 1)
        )
    }
}

struct TipRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number).")
                .font(ClearSplitTheme.Typography.subheadline.weight(.semibold))
                .foregroundColor(.brandPrimary)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .font(ClearSplitTheme.Typography.subheadline)
                .foregroundColor(.textSecondary)

            Spacer()
        }
    }
}
