import SwiftUI

@available(macOS 12.0, iOS 15.0, *)
public final class HealthViewModel: ObservableObject {
    @Published public var statusText: String = "Checking..."
    @Published public var isError: Bool = false

    private let client: HealthChecking

    public init(client: HealthChecking = HealthClient()) {
        self.client = client
    }

    @MainActor
    public func load() async {
        do {
            let response = try await client.fetchHealth()
            statusText = response.status.uppercased()
            isError = false
        } catch {
            statusText = "Error: \(error.localizedDescription)"
            isError = true
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct ContentView: View {
    @StateObject private var viewModel: HealthViewModel

    public init(viewModel: HealthViewModel = HealthViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text(viewModel.statusText)
                .font(.title)
                .foregroundStyle(viewModel.isError ? .red : .green)
            Button("Refresh") {
                Task { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
        .padding()
    }
}

#if DEBUG
@available(macOS 12.0, iOS 15.0, *)
#Preview {
    ContentView()
}
#endif
