import XCTest
@testable import Patcher

final class PatcherTests: XCTestCase {
    func testSkeleton() { XCTAssertEqual(Patcher.requiredLoaderVersion, 6) }
}
