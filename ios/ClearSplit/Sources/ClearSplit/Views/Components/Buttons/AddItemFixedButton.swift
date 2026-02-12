import SwiftUI

struct AddItemFixedButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Text("Add Item")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.blue600)
            .cornerRadius(26)
            .shadow(color: Color.blue600.opacity(0.25), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
