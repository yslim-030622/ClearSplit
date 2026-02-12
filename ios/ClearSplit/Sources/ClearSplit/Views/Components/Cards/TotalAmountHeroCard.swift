import SwiftUI

struct TotalAmountHeroCard: View {
    let totalCents: Int
    let paidByMembershipId: UUID
    let groupMemberships: [Membership]
    let currentUserId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label
            Text("Total Amount")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .padding(.bottom, 8)

            // Amount
            Text(formatCurrency(cents: totalCents, currency: "USD"))
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 12)

            // Paid by
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))

                Text(paidByText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.blue600, Color.blue700],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(24, corners: [.bottomLeft, .bottomRight])
    }

    private var paidByText: String {
        guard let currentUserId = currentUserId else {
            return "Paid by Unknown"
        }

        guard let membership = groupMemberships.first(where: { $0.id == paidByMembershipId }),
              let user = membership.user else {
            return "Paid by Unknown"
        }

        if user.id == currentUserId {
            return "Paid by You"
        }

        return "Paid by \(user.firstName) \(user.lastName)"
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
