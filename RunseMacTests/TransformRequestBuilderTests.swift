import RunseCore
@testable import RunseMac
import XCTest

@MainActor
final class TransformRequestBuilderTests: XCTestCase {
    func testMakeRequestUsesDefaultProviderAndCustomTemplate() throws {
        let fallback = ProviderProfile(
            id: "fallback",
            name: "Fallback",
            kind: .openAICompatible,
            baseURL: "https://fallback.example",
            chatEndpoint: "/v1/chat/completions",
            model: "fallback-model"
        )
        let defaultProfile = ProviderProfile(
            id: "default",
            name: "Default",
            kind: .openAICompatible,
            baseURL: "https://default.example",
            chatEndpoint: "/v1/chat/completions",
            model: "default-model",
            isDefault: true
        )
        let template = PromptTemplate(
            id: "custom-refine",
            action: .refine,
            name: "Custom Refine",
            systemTemplate: "System {{tone}} {{formality}}",
            userTemplate: "User {{selected_text}} {{custom_instruction}} {{length}}"
        )

        let prepared = try TransformRequestBuilder.makeRequest(
            selectedText: "Make this better.",
            action: .refine,
            targetLanguage: "German",
            tone: .professional,
            length: .shorter,
            formality: .formal,
            customInstruction: "Keep terms.",
            profiles: [fallback, defaultProfile],
            templates: [template]
        )

        XCTAssertEqual(prepared.profile.id, "default")
        XCTAssertEqual(prepared.request.model, "default-model")
        XCTAssertEqual(prepared.request.action, .refine)
        XCTAssertEqual(prepared.request.systemPrompt, "System professional formal")
        XCTAssertEqual(prepared.request.userPrompt, "User Make this better. Keep terms. shorter")
    }

    func testMakeRequestFallsBackToBuiltInTranslateTemplate() throws {
        let profile = ProviderProfile.defaultNVIDIA()

        let prepared = try TransformRequestBuilder.makeRequest(
            selectedText: "Hello",
            action: .translate,
            targetLanguage: "Japanese",
            tone: .natural,
            length: .same,
            formality: .neutral,
            customInstruction: "",
            profiles: [profile],
            templates: []
        )

        XCTAssertEqual(prepared.profile.id, RunseConstants.defaultProfileID)
        XCTAssertTrue(prepared.request.userPrompt.contains("Hello"))
        XCTAssertTrue(prepared.request.userPrompt.contains("Japanese"))
        XCTAssertFalse(prepared.request.userPrompt.contains("{{selected_text}}"))
    }

    func testMakeRequestThrowsWhenNoProviderExists() {
        XCTAssertThrowsError(try TransformRequestBuilder.makeRequest(
            selectedText: "Hello",
            action: .refine,
            targetLanguage: "English",
            tone: .natural,
            length: .same,
            formality: .neutral,
            customInstruction: "",
            profiles: [],
            templates: []
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, .invalidURL)
        }
    }
}
