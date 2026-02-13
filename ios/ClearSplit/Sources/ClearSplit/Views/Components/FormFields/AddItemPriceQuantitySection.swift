import SwiftUI

struct AddItemPriceQuantitySection: View {
    @Binding var unitPriceText: String
    @Binding var quantity: Int
    @FocusState.Binding var focusedField: AddItemSheet.Field?
    var formErrors: [String: String]
    var itemTotal: Double
    var onValidationChange: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Unit Price")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray900)
                Text("*")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red500)
            }

            TextField("0.00", text: $unitPriceText)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray900)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(height: 48)
                .background(inputBackground(field: "unitPrice"))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(inputBorder(field: "unitPrice"), lineWidth: inputBorderWidth(field: "unitPrice"))
                )
                .focused($focusedField, equals: .price)
                .onChange(of: unitPriceText) { newValue in
                    if formErrors["unitPrice"] != nil {
                        onValidationChange("unitPrice", newValue)
                    }
                }

            if let error = formErrors["unitPrice"] {
                Text(error)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.red600)
            } else {
                Text("Price per item")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray500)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Quantity")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray900)
                Text("*")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red500)
            }

            HStack(spacing: 12) {
                Button(action: { if quantity > 1 { quantity -= 1 } }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue600)
                }

                TextField("1", value: $quantity, format: .number)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.gray900)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(height: 48)

                Button(action: { quantity += 1 }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue600)
                }
            }
            .frame(height: 48)
            .background(Color.cardInset)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
        }

        HStack {
            Text("Total per item:")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.gray600)

            Spacer()

            Text(String(format: "$%.2f", itemTotal))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.gray900)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.cardInset)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }

    private func inputBackground(field: String) -> Color {
        if formErrors[field] != nil {
            return Color.red50
        }
        if field == "unitPrice" && focusedField == .price {
            return Color.cardBackground
        }
        return Color.cardInset
    }

    private func inputBorder(field: String) -> Color {
        if formErrors[field] != nil {
            return Color.red300
        }
        if field == "unitPrice" && focusedField == .price {
            return Color.blue500
        }
        return Color.borderLight
    }

    private func inputBorderWidth(field: String) -> CGFloat {
        if formErrors[field] != nil {
            return 2
        }
        if field == "unitPrice" && focusedField == .price {
            return 2
        }
        return 1
    }
}
