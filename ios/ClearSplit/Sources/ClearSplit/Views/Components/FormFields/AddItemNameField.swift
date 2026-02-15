import SwiftUI

struct AddItemNameField: View {
    @Binding var itemName: String
    @FocusState.Binding var focusedField: AddItemSheet.Field?
    var formErrors: [String: String]
    var onValidationChange: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.xs) {
            HStack(spacing: 4) {
                Text("Item Name")
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.textPrimary)
                Text("*")
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.danger)
            }

            TextField("e.g., Organic Milk, Apples, Bread", text: $itemName)
                .font(ClearSplitTheme.Typography.body)
                .foregroundColor(.textPrimary)
                .appInputFieldStyle(isFocused: focusedField == .name, hasError: formErrors["name"] != nil)
                .focused($focusedField, equals: .name)
                .onChange(of: itemName) { newValue in
                    if formErrors["name"] != nil {
                        onValidationChange("name", newValue)
                    }
                }

            if let error = formErrors["name"] {
                Text(error)
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.danger)
            } else {
                Text("Give this item a clear name")
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.textTertiary)
            }
        }
    }
}
