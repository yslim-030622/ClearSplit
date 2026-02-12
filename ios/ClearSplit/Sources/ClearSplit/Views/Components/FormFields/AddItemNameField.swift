import SwiftUI

struct AddItemNameField: View {
    @Binding var itemName: String
    @FocusState.Binding var focusedField: AddItemSheet.Field?
    var formErrors: [String: String]
    var onValidationChange: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Item Name")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray900)
                Text("*")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red500)
            }

            TextField("e.g., Organic Milk, Apples, Bread", text: $itemName)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray900)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(height: 48)
                .background(inputBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(inputBorder, lineWidth: inputBorderWidth)
                )
                .overlay(
                    SwiftUI.Group {
                        if focusedField == .name && formErrors["name"] == nil {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue500.opacity(0.1), lineWidth: 4)
                                .padding(-2)
                        }
                    }
                )
                .focused($focusedField, equals: .name)
                .onChange(of: itemName) { newValue in
                    if formErrors["name"] != nil {
                        onValidationChange("name", newValue)
                    }
                }

            if let error = formErrors["name"] {
                Text(error)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.red600)
            } else {
                Text("Give this item a clear name")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray500)
            }
        }
    }

    private var inputBackground: Color {
        if formErrors["name"] != nil {
            return Color.red50
        }
        return Color.white
    }

    private var inputBorder: Color {
        if formErrors["name"] != nil {
            return Color.red300
        }
        return Color.gray200
    }

    private var inputBorderWidth: CGFloat {
        if formErrors["name"] != nil {
            return 2
        }
        return 1
    }
}
