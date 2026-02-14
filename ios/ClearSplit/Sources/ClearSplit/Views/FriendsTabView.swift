import SwiftUI

struct FriendsTabView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.pageBackground
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundColor(.blue600)

                    Text("Friends")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray900)

                    Text("This tab is ready. Share your detailed friend flow and I’ll wire it in.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.gray600)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .padding(.horizontal, 24)
                .cardStyle()
                .padding(.horizontal, 16)
            }
            .navigationTitle("Friends")
        }
    }
}
