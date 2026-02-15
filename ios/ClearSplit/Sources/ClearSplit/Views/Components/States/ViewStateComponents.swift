import SwiftUI

struct LoadingView: View {
    let title: String
    let message: String?

    init(title: String = "Loading...", message: String? = nil) {
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: ClearSplitTheme.Spacing.sm) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.brandPrimary)
                .scaleEffect(1.1)

            Text(title)
                .font(ClearSplitTheme.Typography.bodyStrong)
                .foregroundColor(.textPrimary)

            if let message, !message.isEmpty {
                Text(message)
                    .font(ClearSplitTheme.Typography.subheadline)
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, ClearSplitTheme.Spacing.xl)
        .padding(.horizontal, ClearSplitTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg)
                .stroke(Color.borderMedium, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
        .applyElevation(.low)
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
        VStack(spacing: ClearSplitTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(.textMuted)
                .accessibilityHidden(true)

            Text(title)
                .font(ClearSplitTheme.Typography.title)
                .foregroundColor(.textPrimary)

            Text(message)
                .font(ClearSplitTheme.Typography.body)
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, ClearSplitTheme.Spacing.xs)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .accessibilityHint("Performs an action to continue from the empty state.")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ClearSplitTheme.Spacing.lg)
        .padding(.vertical, ClearSplitTheme.Spacing.xl)
        .background(Color.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg)
                .stroke(Color.borderMedium, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
        .applyElevation(.low)
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
        VStack(spacing: ClearSplitTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(.danger)
                .accessibilityHidden(true)

            Text(title)
                .font(ClearSplitTheme.Typography.sectionTitle)
                .foregroundColor(.textPrimary)

            Text(message)
                .font(ClearSplitTheme.Typography.subheadline)
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)

            Button(retryTitle, action: retry)
                .padding(.top, ClearSplitTheme.Spacing.xs)
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityLabel("Retry")
                .accessibilityHint("Retries loading data.")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ClearSplitTheme.Spacing.lg)
        .padding(.vertical, ClearSplitTheme.Spacing.lg)
        .background(Color.dangerSurface)
        .overlay(
            RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg)
                .stroke(Color.red300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
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
        VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.sm) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(ClearSplitTheme.Typography.sectionTitle)
                    .foregroundColor(.textPrimary)
            }

            content
        }
        .padding(ClearSplitTheme.Spacing.md)
        .cardStyle()
    }
}
