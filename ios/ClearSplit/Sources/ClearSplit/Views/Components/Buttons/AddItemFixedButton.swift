import SwiftUI

struct AddItemFixedButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.textOnBrand)

                Text("Add Item")
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.textOnBrand)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.pill))
    }
}
