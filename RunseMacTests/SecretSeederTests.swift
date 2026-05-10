import RunseCore
import XCTest

final class SecretSeederTests: XCTestCase {
    func testSeedDefaultNVIDIAStoresBuildSettingValue() async throws {
        let store = InMemorySecretStore()

        try await SecretSeeder.seedDefaultNVIDIAIfNeeded(
            secretStore: store,
            buildSettingValue: " default-key "
        )

        let saved = try await store.load(
            service: SecretSeeder.service,
            account: RunseConstants.defaultProfileID
        )
        XCTAssertEqual(saved, "default-key")
    }

    func testSeedDefaultNVIDIAReplacesBlankExistingValue() async throws {
        let store = InMemorySecretStore()
        try await store.save(
            "   ",
            service: SecretSeeder.service,
            account: RunseConstants.defaultProfileID
        )

        try await SecretSeeder.seedDefaultNVIDIAIfNeeded(
            secretStore: store,
            buildSettingValue: "default-key"
        )

        let saved = try await store.load(
            service: SecretSeeder.service,
            account: RunseConstants.defaultProfileID
        )
        XCTAssertEqual(saved, "default-key")
    }

    func testSeedDefaultNVIDIAKeepsNonBlankExistingValue() async throws {
        let store = InMemorySecretStore()
        try await store.save(
            "user-key",
            service: SecretSeeder.service,
            account: RunseConstants.defaultProfileID
        )

        try await SecretSeeder.seedDefaultNVIDIAIfNeeded(
            secretStore: store,
            buildSettingValue: "default-key"
        )

        let saved = try await store.load(
            service: SecretSeeder.service,
            account: RunseConstants.defaultProfileID
        )
        XCTAssertEqual(saved, "user-key")
    }

    func testSeedDefaultNVIDIAIgnoresBlankBuildSettingValue() async throws {
        let store = InMemorySecretStore()

        try await SecretSeeder.seedDefaultNVIDIAIfNeeded(
            secretStore: store,
            buildSettingValue: "   "
        )

        let saved = try await store.load(
            service: SecretSeeder.service,
            account: RunseConstants.defaultProfileID
        )
        XCTAssertNil(saved)
    }

    func testKeychainAccessGroupIgnoresUnresolvedBuildSetting() {
        XCTAssertNil(KeychainAccessGroup.make(appIdentifierPrefix: "$(AppIdentifierPrefix)"))
    }

    func testKeychainAccessGroupUsesConcretePrefix() {
        XCTAssertEqual(
            KeychainAccessGroup.make(appIdentifierPrefix: "SK4GFF6AHN."),
            "SK4GFF6AHN.io.github.madeye.runse.shared"
        )
    }
}
