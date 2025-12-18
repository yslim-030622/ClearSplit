import XCTest
@testable import ClearSplit

final class ClearSplitTests: XCTestCase {
    func testHealthResponseDecoding() throws {
        let json = #"{"status":"ok"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(HealthResponse.self, from: data)
        XCTAssertEqual(decoded.status, "ok")
    }
}
