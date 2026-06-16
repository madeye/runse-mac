import RunseCore
import SwiftData
import XCTest

final class BootstrapTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appending(path: "BootstrapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        try super.tearDownWithError()
    }

    func testModelContainerOpensFreshStore() throws {
        let storeURL = directory.appending(path: "Runse.sqlite")

        let container = try Bootstrap.modelContainer(at: storeURL)

        XCTAssertNotNil(container)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testModelContainerRecoversFromCorruptStore() throws {
        let fm = FileManager.default
        let storeURL = directory.appending(path: "Runse.sqlite")

        // Simulate the historical launch-crash trigger: an on-disk store that
        // SwiftData cannot open (corrupt bytes / schema-incompatible file).
        let garbage = Data("this is not a valid sqlite database".utf8)
        try garbage.write(to: storeURL)

        // Recovery must NOT throw — the bad store is quarantined and a fresh,
        // openable store is created in its place.
        let container = try Bootstrap.modelContainer(at: storeURL)
        XCTAssertNotNil(container)

        // A fresh store now lives at the original path, and it is no longer the
        // garbage we wrote (i.e. it was actually replaced, not reused).
        XCTAssertTrue(fm.fileExists(atPath: storeURL.path))
        let storeAfter = try Data(contentsOf: storeURL)
        XCTAssertNotEqual(storeAfter, garbage)

        // The corrupt original was moved aside rather than destroyed.
        let quarantined = try fm.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("Runse.sqlite.corrupt-") }
        XCTAssertFalse(quarantined.isEmpty, "Expected the corrupt store to be quarantined")
    }

    @MainActor
    func testRecoveredContainerIsUsable() throws {
        let storeURL = directory.appending(path: "Runse.sqlite")
        try Data("corrupt".utf8).write(to: storeURL)

        let container = try Bootstrap.modelContainer(at: storeURL)

        // The recovered store must be a working container: seeding the defaults
        // (insert + save) succeeds against it.
        let context = ModelContext(container)
        try Bootstrap.seedDefaultsIfNeeded(context: context)

        var descriptor = FetchDescriptor<ProviderProfile>()
        descriptor.fetchLimit = 1
        XCTAssertFalse(try context.fetch(descriptor).isEmpty)
    }
}
