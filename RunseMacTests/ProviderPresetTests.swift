import XCTest
@testable import RunseCore

final class ProviderPresetTests: XCTestCase {
    func test_customCase_hasNoConfiguration() {
        XCTAssertNil(ProviderPreset.custom.configuration)
    }

    func test_namedPresets_eachHaveDistinctConfiguration() {
        let configs = ProviderPreset.allCases.compactMap(\.configuration)
        XCTAssertEqual(configs.count, ProviderPreset.allCases.count - 1, "Only .custom should lack a configuration")
        let names = Set(configs.map(\.name))
        XCTAssertEqual(names.count, configs.count, "Preset names must be unique")
        let baseURLs = Set(configs.map(\.baseURL))
        XCTAssertEqual(baseURLs.count, configs.count, "Preset base URLs must be unique")
    }

    func test_infer_matchesByBaseURLAndModel() {
        for preset in ProviderPreset.allCases {
            guard let configuration = preset.configuration else { continue }
            let profile = ProviderProfile(
                name: "anything",
                kind: configuration.kind,
                baseURL: configuration.baseURL,
                chatEndpoint: configuration.endpoint,
                model: configuration.model
            )
            XCTAssertEqual(ProviderPreset.infer(from: profile), preset)
        }
    }

    func test_infer_returnsCustom_forUnknownProfile() {
        let profile = ProviderProfile(
            name: "Unknown",
            kind: .openAICompatible,
            baseURL: "https://example.invalid",
            chatEndpoint: "/v1/chat/completions",
            model: "mystery-model"
        )
        XCTAssertEqual(ProviderPreset.infer(from: profile), .custom)
    }

    func test_infer_returnsCustom_forNilProfile() {
        XCTAssertEqual(ProviderPreset.infer(from: nil), .custom)
    }

    func test_allPresetNames_containsEveryNonCustomName() {
        let names = ProviderPreset.allPresetNames
        for preset in ProviderPreset.allCases where preset != .custom {
            XCTAssertTrue(names.contains(preset.configuration!.name), "Missing name for \(preset)")
        }
    }
}
