import Foundation

/// Represents an item extracted from a receipt with OCR
struct ExtractedItem: Identifiable, Codable {
    let id: String
    var name: String
    var price: Double
    var quantity: Int
    var confidence: ConfidenceLevel
    
    enum ConfidenceLevel: String, Codable {
        case high
        case medium
        case low
        
        var color: String {
            switch self {
            case .high: return "green"
            case .medium: return "yellow"
            case .low: return "orange"
            }
        }
        
        var displayName: String {
            rawValue.capitalized
        }
        
        var needsWarning: Bool {
            self == .low
        }
    }
    
    var totalPrice: Double {
        price * Double(quantity)
    }
}
