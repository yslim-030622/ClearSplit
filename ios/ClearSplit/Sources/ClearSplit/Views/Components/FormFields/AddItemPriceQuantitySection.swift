import SwiftUI

struct AddItemPriceQuantitySection: View {
    @Binding var unitPriceText: String
    @Binding var quantity: Int
    @FocusState.Binding var focusedField: AddItemSheet.Field?
    var formErrors: [String: String]
    var itemTotal: Double
    var onValidationChange: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.xs) {
            HStack(spacing: 4) {
                Text("Unit Price")
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.textPrimary)
                Text("*")
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.danger)
            }

            TextField("0.00", text: $unitPriceText)
                .font(ClearSplitTheme.Typography.body)
                .foregroundColor(.textPrimary)
                .keyboardType(.decimalPad)
                .appInputFieldStyle(isFocused: focusedField == .price, hasError: formErrors["unitPrice"] != nil)
                .focused($focusedField, equals: .price)
                .onChange(of: unitPriceText) { newValue in
                    if formErrors["unitPrice"] != nil {
                        onValidationChange("unitPrice", newValue)
                    }
                }

            if let error = formErrors["unitPrice"] {
                Text(error)
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.danger)
            } else {
                Text("Price per item")
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.textTertiary)
            }
        }

        VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.xs) {
            HStack(spacing: 4) {
                Text("Quantity")
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.textPrimary)
                Text("*")
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.danger)
            }

            HStack(spacing: 12) {
                Button(action: { if quantity > 1 { quantity -= 1 } }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.brandPrimary)
                }

                TextField("1", value: $quantity, format: .number)
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.textPrimary)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(height: 48)

                Button(action: { quantity += 1 }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.brandPrimary)
                }
            }
            .frame(height: 48)
            .background(Color.cardInset)
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
        }

        HStack {
            Text("Total per item:")
                .font(ClearSplitTheme.Typography.subheadline)
                .foregroundColor(.textSecondary)

            Spacer()

            Text(String(format: "$%.2f", itemTotal))
                .font(ClearSplitTheme.Typography.bodyStrong)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.cardInset)
        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
}
