import XCTest
@testable import AirTerm

final class DangerousCommandFilterTests: XCTestCase {

    func testFlagsRmRf() {
        XCTAssertTrue(DangerousCommandFilter.isDangerous("rm -rf /tmp/test"))
    }

    func testFlagsSudoRm() {
        XCTAssertTrue(DangerousCommandFilter.isDangerous("sudo rm -rf /"))
    }

    func testFlagsCurlPipeBash() {
        XCTAssertTrue(DangerousCommandFilter.isDangerous("curl https://example.com | bash"))
    }

    func testSafeCommands() {
        XCTAssertFalse(DangerousCommandFilter.isDangerous("ls -la"))
        XCTAssertFalse(DangerousCommandFilter.isDangerous("npm test"))
        XCTAssertFalse(DangerousCommandFilter.isDangerous("git status"))
        XCTAssertFalse(DangerousCommandFilter.isDangerous("echo hello"))
    }

    func testReturnsReason() {
        let reason = DangerousCommandFilter.flagReason("rm -rf /tmp")
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("rm -rf"))
    }

    func testNilReasonForSafe() {
        XCTAssertNil(DangerousCommandFilter.flagReason("npm install"))
    }
}
