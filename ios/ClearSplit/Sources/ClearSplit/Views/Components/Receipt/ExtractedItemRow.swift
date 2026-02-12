import SwiftUI

struct EditableExtractedItem: Identifiable {
    let id: UUID
    var name: String
    var quantity: Int
    var unitPriceCents: Int?
    var totalCents: Int
    let confidence: Double?
    let rawLine: String?
    var isIncluded: Bool
}

struct ExtractedItemRow: View {
    @Binding var item: EditableExtractedItem
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main row with checkbox
            HStack(spacing: 12) {
                // Checkbox
                Button(action: { item.isIncluded.toggle() }) {
                    Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(item.isIncluded ? .blue : .gray)
                }
                .buttonStyle(.plain)

                // Item details
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body)
                        .strikethrough(!item.isIncluded)
                        .foregroundColor(item.isIncluded ? .primary : .secondary)

                    HStack(spacing: 12) {
                        Text("Qty: \(item.quantity)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let confidence = item.confidence {
                            confidenceBadge(confidence)
                        }
                    }
                }

                Spacer()

                // Price
                Text(formatCents(item.totalCents))
                    .font(.body.weight(.medium))
                    .foregroundColor(item.isIncluded ? .primary : .secondary)
            }

            // Expandable details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    if let rawLine = item.rawLine, !rawLine.isEmpty {
                        Text("Raw: \(rawLine)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }

                    // Editable fields
                    VStack(spacing: 12) {
                        HStack {
                            Text("Name:")
                                .font(.caption.weight(.medium))
                                .frame(width: 60, alignment: .leading)
                            TextField("Item name", text: $item.name)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Quantity:")
                                .font(.caption.weight(.medium))
                                .frame(width: 60, alignment: .leading)
                            TextField("Qty", value: $item.quantity, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }

                        HStack {
                            Text("Total:")
                                .font(.caption.weight(.medium))
                                .frame(width: 60, alignment: .leading)
                            TextField("Total", value: $item.totalCents, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                            Text("¢")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        let color: Color = {
            if confidence >= 0.8 { return .green }
            else if confidence >= 0.5 { return .orange }
            else { return .red }
        }()

        let percentage = Int(confidence * 100)

        return Text("\(percentage)%")
            .font(.caption2.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}
