import SwiftUI

/// View for reviewing and confirming OCR-extracted items from a receipt
public struct ExtractedItemsReviewView: View {
    let sessionId: UUID
    let groupId: UUID
    let receiptUploadId: UUID
    let participants: [ShoppingSessionParticipant]
    let appState: AppState

    @Environment(\.dismiss) private var dismiss

    @State private var extractedItems: [EditableExtractedItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isConfirming = false

    public var body: some View {
        NavigationView {
            ZStack {
                if isLoading {
                    ProgressView("Extracting items from receipt...")
                        .padding()
                } else if let error = error {
                    ExtractedItemsErrorState(message: error) {
                        dismiss()
                    }
                } else if extractedItems.isEmpty {
                    ExtractedItemsEmptyState {
                        dismiss()
                    }
                } else {
                    ExtractedItemsList(
                        extractedItems: $extractedItems,
                        onSelectAll: selectAll
                    )
                }
            }
            .navigationTitle("Review Extracted Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if !extractedItems.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Confirm") {
                            confirmItems()
                        }
                        .disabled(isConfirming || !hasSelectedItems)
                    }
                }
            }
        }
        .task {
            await loadExtractedItems()
        }
    }

    private var hasSelectedItems: Bool {
        extractedItems.contains { $0.isIncluded }
    }

    private func selectAll() {
        for index in extractedItems.indices {
            extractedItems[index].isIncluded = true
        }
    }

    private func loadExtractedItems() async {
        isLoading = true
        error = nil

        do {
            let items = try await appState.shoppingService.extractReceiptItems(
                receiptUploadId: receiptUploadId
            )

            extractedItems = items.map { item in
                EditableExtractedItem(
                    id: item.id,
                    name: item.name,
                    quantity: item.quantity,
                    unitPriceCents: item.unitPriceCents,
                    totalCents: item.totalCents,
                    confidence: item.confidence,
                    rawLine: item.rawLine,
                    isIncluded: true
                )
            }

            isLoading = false
        } catch let apiError as APIError {
            switch apiError {
            case .server(let status, let message) where status == 403:
                self.error = "Only the payer can extract items from receipts. \(message ?? "")"
            case .unauthorized:
                self.error = "You are not authorized. Please log in again."
            default:
                self.error = "Failed to extract items: \(apiError.localizedDescription)"
            }
            isLoading = false
        } catch {
            self.error = "Failed to extract items: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func confirmItems() {
        isConfirming = true

        Task {
            do {
                let participantIds = participants.map { $0.membershipId }

                for item in extractedItems where item.isIncluded {
                    let createRequest = ShoppingItemCreate(
                        name: item.name,
                        quantity: item.quantity,
                        unitPriceCents: item.unitPriceCents,
                        totalCents: item.totalCents
                    )

                    let createdItem = try await appState.shoppingService.createItem(
                        sessionId: sessionId,
                        request: createRequest
                    )

                    if !participantIds.isEmpty {
                        let sharersRequest = SharersSetRequest(membershipIds: participantIds)
                        _ = try await appState.shoppingService.setSharers(
                            itemId: createdItem.id,
                            request: sharersRequest
                        )
                    }
                }

                _ = try await appState.shoppingService.getSession(sessionId: sessionId)

                await MainActor.run {
                    isConfirming = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to create items: \(error.localizedDescription)"
                    isConfirming = false
                }
            }
        }
    }
}
