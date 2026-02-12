import SwiftUI

struct ExtractedItemsList: View {
    @Binding var extractedItems: [EditableExtractedItem]
    var onSelectAll: () -> Void

    var selectedItemsCount: Int {
        extractedItems.filter { $0.isIncluded }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with count
            HStack {
                Text("\(selectedItemsCount) of \(extractedItems.count) items selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onSelectAll) {
                    Text("Select All")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            // Items list
            List {
                ForEach($extractedItems) { $item in
                    ExtractedItemRow(item: $item)
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}
