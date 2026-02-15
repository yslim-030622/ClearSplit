import SwiftUI

struct ReceiptThumbnailView: View {
    let receipt: ReceiptUpload
    let appState: AppState
    let canDelete: Bool
    let onDeleteTap: (ReceiptUpload) -> Void

    @State private var imageURL: URL?
    @State private var isLoading = true
    @State private var loadError = false

    var body: some View {
        contentView
            .task {
                await loadImageURL()
            }
            .contextMenu {
                if canDelete {
                    Button(role: .destructive) {
                        onDeleteTap(receipt)
                    } label: {
                        Label("Delete Receipt", systemImage: "trash")
                    }
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        if let url = imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    loadingView
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                                .stroke(Color.borderMedium, lineWidth: 1)
                        )
                case .failure(let error):
                    errorView
                        .onAppear {
                            print("[ReceiptThumbnailView] ❌ AsyncImage failed to load image")
                            print("[ReceiptThumbnailView] URL: \(url.absoluteString)")
                            print("[ReceiptThumbnailView] Error: \(error.localizedDescription)")
                            if let urlError = error as? URLError {
                                print("[ReceiptThumbnailView] URLError code: \(urlError.code.rawValue)")
                                print("[ReceiptThumbnailView] URLError description: \(urlError.localizedDescription)")
                            }
                        }
                @unknown default:
                    loadingView
                }
            }
            .onAppear {
                // Test URL reachability when view appears
                Task {
                    await testURLReachability(url: url)
                }
            }
        } else if isLoading {
            loadingView
        } else {
            errorView
        }
    }

    private var loadingView: some View {
        RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
            .fill(Color.cardInset)
            .frame(width: 80, height: 80)
            .overlay(
                ProgressView()
                    .scaleEffect(0.8)
            )
    }

    private var errorView: some View {
        RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
            .fill(Color.cardInset)
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.textMuted)
            )
    }

    private func loadImageURL() async {
        // Avoid refetching if we already have a URL
        guard imageURL == nil && isLoading else {
            print("[ReceiptThumbnailView] Skipping load - already have URL or not loading. receiptId=\(receipt.id), hasURL=\(imageURL != nil), isLoading=\(isLoading)")
            return
        }

        print("[ReceiptThumbnailView] Starting to load download URL for receipt: \(receipt.id)")

        do {
            let urlString = try await appState.getReceiptDownloadURL(receiptUploadId: receipt.id)
            print("[ReceiptThumbnailView] Received URL string: \(urlString)")
            print("[ReceiptThumbnailView] URL scheme: \(URL(string: urlString)?.scheme ?? "nil")")
            print("[ReceiptThumbnailView] URL host: \(URL(string: urlString)?.host ?? "nil")")

            if let url = URL(string: urlString) {
                print("[ReceiptThumbnailView] Successfully created URL object: \(url)")

                // Test URL reachability immediately
                await testURLReachability(url: url)

                await MainActor.run {
                    self.imageURL = url
                    self.isLoading = false
                    print("[ReceiptThumbnailView] Set imageURL and cleared loading state")
                }
            } else {
                print("[ReceiptThumbnailView] ❌ Failed to create URL from string: '\(urlString)'")
                print("[ReceiptThumbnailView] URL string length: \(urlString.count)")
                print("[ReceiptThumbnailView] URL string contains percent encoding: \(urlString.contains("%"))")
                await MainActor.run {
                    self.loadError = true
                    self.isLoading = false
                }
            }
        } catch {
            print("[ReceiptThumbnailView] ❌ Failed to load image URL for receipt \(receipt.id)")
            print("[ReceiptThumbnailView] Error type: \(type(of: error))")
            print("[ReceiptThumbnailView] Error description: \(error.localizedDescription)")
            if let apiError = error as? APIError {
                switch apiError {
                case .server(let status, let message):
                    print("[ReceiptThumbnailView] API Error - Status: \(status), Message: \(message ?? "nil")")
                case .unauthorized:
                    print("[ReceiptThumbnailView] API Error - Unauthorized (401)")
                case .decoding:
                    print("[ReceiptThumbnailView] API Error - Decoding failed")
                case .network(let underlyingError):
                    print("[ReceiptThumbnailView] API Error - Network error: \(underlyingError)")
                }
            }
            await MainActor.run {
                self.loadError = true
                self.isLoading = false
            }
        }
    }

    private func testURLReachability(url: URL) async {
        print("[ReceiptThumbnailView] 🔍 Testing URL reachability: \(url.absoluteString)")
        print("[ReceiptThumbnailView] URL scheme: \(url.scheme ?? "nil")")
        print("[ReceiptThumbnailView] URL host: \(url.host ?? "nil")")
        print("[ReceiptThumbnailView] URL path: \(url.path)")

        // Check for ATS restrictions
        if url.scheme == "http" {
            print("[ReceiptThumbnailView] ⚠️ WARNING: URL uses HTTP (not HTTPS) - ATS may block this!")
            print("[ReceiptThumbnailView] ⚠️ Need to add ATS exception in Info.plist for host: \(url.host ?? "unknown")")
        }

        // Manual URL fetch test
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0

            print("[ReceiptThumbnailView] 📡 Starting manual URL fetch test...")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("[ReceiptThumbnailView] ✅ Manual fetch succeeded!")
                print("[ReceiptThumbnailView] HTTP Status: \(httpResponse.statusCode)")
                print("[ReceiptThumbnailView] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
                print("[ReceiptThumbnailView] Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "nil")")
                print("[ReceiptThumbnailView] Data size: \(data.count) bytes")

                if httpResponse.statusCode == 200 {
                    print("[ReceiptThumbnailView] ✅ URL is reachable and returns 200 OK")
                    // Check if it's actually an image
                    if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                        print("[ReceiptThumbnailView] Content-Type: \(contentType)")
                        if contentType.hasPrefix("image/") {
                            print("[ReceiptThumbnailView] ✅ Response is an image")
                        } else {
                            print("[ReceiptThumbnailView] ⚠️ Response is not an image: \(contentType)")
                        }
                    }
                } else {
                    print("[ReceiptThumbnailView] ❌ URL returned non-200 status: \(httpResponse.statusCode)")
                    if let responseBody = String(data: data, encoding: .utf8) {
                        print("[ReceiptThumbnailView] Response body: \(responseBody.prefix(200))")
                    }
                }
            } else {
                print("[ReceiptThumbnailView] ⚠️ Response is not HTTPURLResponse")
            }
        } catch {
            print("[ReceiptThumbnailView] ❌ Manual URL fetch failed!")
            print("[ReceiptThumbnailView] Error: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                print("[ReceiptThumbnailView] URLError code: \(urlError.code.rawValue)")
                print("[ReceiptThumbnailView] URLError description: \(urlError.localizedDescription)")

                switch urlError.code {
                case .notConnectedToInternet:
                    print("[ReceiptThumbnailView] ❌ Network connection issue")
                case .timedOut:
                    print("[ReceiptThumbnailView] ❌ Request timed out")
                case .cannotFindHost:
                    print("[ReceiptThumbnailView] ❌ Cannot find host - DNS issue")
                case .cannotConnectToHost:
                    print("[ReceiptThumbnailView] ❌ Cannot connect to host")
                case .networkConnectionLost:
                    print("[ReceiptThumbnailView] ❌ Network connection lost")
                case .appTransportSecurityRequiresSecureConnection:
                    print("[ReceiptThumbnailView] ❌ ATS blocked HTTP connection - need HTTPS or ATS exception")
                default:
                    print("[ReceiptThumbnailView] ❌ Other URLError: \(urlError)")
                }
            }
        }
    }
}
