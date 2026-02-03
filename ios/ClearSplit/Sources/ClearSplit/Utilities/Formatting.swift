import Foundation

// MARK: - Currency Formatting

public func formatCurrency(cents: Int, currency: String) -> String {
    let amount = Double(cents) / 100.0
    return String(format: "$%.2f", amount)
}

// MARK: - Date Formatting

public func formatDateString(_ dateString: String?) -> String {
    guard let dateString = dateString else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    if let date = formatter.date(from: dateString) {
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    return dateString
}

public func parseDateString(_ dateString: String?) -> Date? {
    guard let dateString = dateString else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: dateString)
}
