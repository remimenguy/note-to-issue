import Combine
import XCTest
@testable import NoteToIssue

final class AppLifecycleTests: XCTestCase {
    @MainActor
    func testModelStartsWithoutOpeningAWindow() async {
        let loaded = expectation(description: "Model boots without a window")
        let model = AppModel(demo: true)
        let observation = model.$entries.dropFirst().sink { entries in
            if !entries.isEmpty { loaded.fulfill() }
        }
        await fulfillment(of: [loaded], timeout: 3)
        XCTAssertEqual(model.entries.count, 1)
        XCTAssertFalse(model.monitoring)
        withExtendedLifetime(observation) {}
    }
}
