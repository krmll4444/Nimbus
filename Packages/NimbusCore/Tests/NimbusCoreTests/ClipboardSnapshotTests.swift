import XCTest
@testable import NimbusCore

final class ClipboardSnapshotTests: XCTestCase {
    func testTextFingerprintIsStable() {
        let a = ClipboardSnapshot.fingerprint(forText: "nimbus")
        let b = ClipboardSnapshot.fingerprint(forText: "nimbus")
        let c = ClipboardSnapshot.fingerprint(forText: "other")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testImageFingerprintMatchesSamePixels() {
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let a = ClipboardSnapshot.fingerprint(forImageData: png)
        let b = ClipboardSnapshot.fingerprint(forImageData: Data(png))
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix("image-px:") || a.hasPrefix("image-bytes:"))
    }

    func testSnapshotCarriesSource() {
        let source = ClipboardSource(bundleID: "com.apple.Safari", name: "Safari")
        let snap = ClipboardSnapshot(payload: .text("hi"), source: source)
        XCTAssertEqual(snap.source?.bundleID, "com.apple.Safari")
        XCTAssertEqual(snap.source?.name, "Safari")
    }
}
