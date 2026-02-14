import SwiftUI

struct LoadingView: View {
    let title: String
    let message: String?

    init(title: String = "Loading...", message: String? = nil) {
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.blue600)
                .scaleEffect(1.1)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.gray900)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray500)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderMedium, lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(.gray400)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.gray900)

            Text(message)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue600)
                    .accessibilityHint("Performs an action to continue from the empty state.")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(Color.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderMedium, lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    let retryTitle: String
    let retry: () -> Void

    init(
        title: String = "Something went wrong",
        message: String,
        retryTitle: String = "Try Again",
        retry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(.red600)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.gray900)

            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.gray500)
                .multilineTextAlignment(.center)

            Button(retryTitle, action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.blue600)
                .accessibilityLabel("Retry")
                .accessibilityHint("Retries loading data.")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(Color.red50)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red300, lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

struct SectionCardView<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.gray900)
            }

            content
        }
        .padding(16)
        .cardStyle()
    }
}
