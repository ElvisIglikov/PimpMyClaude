import XCTest
@testable import ClaudeAX

final class ClaudeAXTests: XCTestCase {
    func testSkeleton() { XCTAssertEqual(ClaudeCommand.allCases.count, 7) }
}
