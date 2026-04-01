import XCTest
@testable import AirTerm

final class BundleIDValidatorTests: XCTestCase {

    func testAllowsTerminalApp() {
        XCTAssertTrue(BundleIDValidator.isAllowed("com.apple.Terminal"))
    }

    func testAllowsiTerm2() {
        XCTAssertTrue(BundleIDValidator.isAllowed("com.googlecode.iterm2"))
    }

    func testAllowsWarp() {
        XCTAssertTrue(BundleIDValidator.isAllowed("dev.warp.Warp-Stable"))
    }

    func testAllowsGhostty() {
        XCTAssertTrue(BundleIDValidator.isAllowed("com.mitchellh.ghostty"))
    }

    func testRejectsSafari() {
        XCTAssertFalse(BundleIDValidator.isAllowed("com.apple.Safari"))
    }

    func testRejectsUnknown() {
        XCTAssertFalse(BundleIDValidator.isAllowed("com.example.malicious"))
    }

    func testValidateReadAllowed() {
        let result = BundleIDValidator.validateRead(bundleId: "com.apple.Terminal")
        if case .failure = result {
            XCTFail("Should allow Terminal.app")
        }
    }

    func testValidateReadRejected() {
        let result = BundleIDValidator.validateRead(bundleId: "com.apple.Safari")
        if case .success = result {
            XCTFail("Should reject Safari")
        }
    }

    func testValidateWriteRejected() {
        let result = BundleIDValidator.validateWrite(bundleId: "com.apple.Finder")
        if case .success = result {
            XCTFail("Should reject Finder")
        }
    }
}
