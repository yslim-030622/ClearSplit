import Foundation

/// Returned with HTTP 202 when extract-items enqueues OCR.
struct JobAcceptedResponse: Codable {
    let jobId: UUID
    let status: String
    let statusUrl: String
}

/// Full job status from GET /jobs/{id}.
struct JobStatusResponse: Codable {
    let id: UUID
    let type: String
    let status: String
    let attempt: Int
    let maxAttempts: Int
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let lastError: String?
    // Backend `result_summary` is arbitrary JSONB (e.g. {"item_count": 5}).
    // Using [String: AnyCodableValue] would require a custom wrapper.
    // For MVP, decode only known keys via a dedicated struct:
    let resultSummary: JobResultSummary?
}

/// Typed wrapper for the `result_summary` JSONB field.
/// Add new keys here as the backend evolves — avoids silent decode failures.
struct JobResultSummary: Codable {
    let itemCount: Int?
}
