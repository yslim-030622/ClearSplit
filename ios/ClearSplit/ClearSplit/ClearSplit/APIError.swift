//
//  APIError.swift
//  ClearSplit
//
//  API error types
//

import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case unauthorized
    case decodingError(Error)
    case validationError(String) // 422 Unprocessable Entity
    case serverError(Int, String?)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized. Please log in again."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .validationError(let message):
            return message
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
