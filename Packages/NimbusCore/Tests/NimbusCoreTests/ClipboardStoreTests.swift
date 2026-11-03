import XCTest
@testable import NimbusCore

@MainActor
final class ClipboardStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var store: ClipboardStore!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NimbusTests-\(UUID().uuidString)", isDirectory: true)
        store = ClipboardStore(rootURL: tempRoot)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        store = nil
        tempRoot = nil
    }

    func testIngestsTextAndLink() {
        store.ingest(ClipboardSnapshot(payload: .text("hello nimbus")))
        store.ingest(ClipboardSnapshot(payload: .text("https://example.com")))

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items[0].type, .link)
        XCTAssertEqual(store.items[1].type, .text)
    }

    func testIgnoresImmediateDuplicateFingerprint() {
        let snap = ClipboardSnapshot(payload: .text("same"))
        store.ingest(snap)
        store.ingest(snap)

        XCTAssertEqual(store.items.count, 1)
    }

    func testPromotesExistingDuplicateInsteadOfInserting() {
        store.ingest(ClipboardSnapshot(payload: .text("first")))
        store.ingest(ClipboardSnapshot(payload: .text("second")))
        store.ingest(ClipboardSnapshot(payload: .text("first")))

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items[0].text, "first")
        XCTAssertEqual(store.items[1].text, "second")
    }

    func testClearKeepsPinned() {
        store.ingest(ClipboardSnapshot(payload: .text("keep")))
        store.ingest(ClipboardSnapshot(payload: .text("drop")))
        let keep = store.items.first(where: { $0.text == "keep" })!
        store.togglePin(keep)
        store.clearAll(keepingPinned: true)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].text, "keep")
        XCTAssertTrue(store.items[0].isPinned)
    }

    func testClearAllRemovesEverythingWhenNotKeepingPinned() {
        store.ingest(ClipboardSnapshot(payload: .text("a")))
        store.ingest(ClipboardSnapshot(payload: .text("b")))
        store.togglePin(store.items[0])
        store.clearAll(keepingPinned: false)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testImageIngestPersistsOwnedCopy() {
        let png = Self.tinyPNG
        let item = store.ingest(ClipboardSnapshot(payload: .image(png)))

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.type, .image)
        XCTAssertNotNil(item?.imageFileName)
        XCTAssertEqual(store.imageData(for: item!), png)

        let fileURL = tempRoot
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(item!.imageFileName!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testImageDuplicateIsDedupedByFingerprint() {
        let png = Self.tinyPNG
        store.ingest(ClipboardSnapshot(payload: .image(png)))
        store.ingest(ClipboardSnapshot(payload: .text("spacer")))
        store.ingest(ClipboardSnapshot(payload: .image(png)))

        XCTAssertEqual(store.items.filter { $0.type == .image }.count, 1)
        XCTAssertEqual(store.items[0].type, .image)
    }

    func testMaxItemsTrimsUnpinnedButKeepsPinned() {
        store.maxItemsLimit = 3
        store.ingest(ClipboardSnapshot(payload: .text("pin-me")))
        store.togglePin(store.items[0])

        store.ingest(ClipboardSnapshot(payload: .text("a")))
        store.ingest(ClipboardSnapshot(payload: .text("b")))
        store.ingest(ClipboardSnapshot(payload: .text("c")))
        store.ingest(ClipboardSnapshot(payload: .text("d")))

        XCTAssertEqual(store.items.count, 3)
        XCTAssertTrue(store.items.contains(where: { $0.text == "pin-me" && $0.isPinned }))
        XCTAssertFalse(store.items.contains(where: { $0.text == "a" }))
    }

    func testDeleteRemovesItemAndImageFile() {
        let item = store.ingest(ClipboardSnapshot(payload: .image(Self.tinyPNG)))!
        let name = item.imageFileName!
        let fileURL = tempRoot.appendingPathComponent("images/\(name)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.delete(item)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testUpdateTextChangesTypeWhenBecomesLink() {
        let item = store.ingest(ClipboardSnapshot(payload: .text("plain")))!
        XCTAssertTrue(store.updateText(for: item.id, text: "https://nimbus.app"))
        XCTAssertEqual(store.items[0].type, .link)
        XCTAssertEqual(store.items[0].text, "https://nimbus.app")
    }

    func testUpdateOCRTextPersists() {
        let item = store.ingest(ClipboardSnapshot(payload: .image(Self.tinyPNG)))!
        store.updateOCRText(for: item.id, text: "hello from ocr")
        XCTAssertEqual(store.items[0].ocrText, "hello from ocr")
    }

    func testPersistsAcrossRelaunch() {
        store.ingest(ClipboardSnapshot(payload: .text("survives")))
        store.ingest(ClipboardSnapshot(payload: .image(Self.tinyPNG)))

        let reloaded = ClipboardStore(rootURL: tempRoot)
        XCTAssertEqual(reloaded.items.count, 2)
        XCTAssertTrue(reloaded.items.contains(where: { $0.type == .text && $0.text == "survives" }))
        XCTAssertTrue(reloaded.items.contains(where: { $0.type == .image }))
        XCTAssertNotNil(reloaded.items.first(where: { $0.type == .image }).flatMap { reloaded.imageData(for: $0) })
    }

    func testIgnoresEmptyText() {
        XCTAssertNil(store.ingest(ClipboardSnapshot(payload: .text("   "))))
        XCTAssertTrue(store.items.isEmpty)
    }

    private static let tinyPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!
}
