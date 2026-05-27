import Foundation
import RunseCore
import SwiftData

@MainActor
struct TransformRunner {
    let modelContext: ModelContext
    let profiles: [ProviderProfile]
    let templates: [PromptTemplate]

    func run(
        selectedText: String,
        action: TransformAction,
        targetLanguage: String,
        tone: Tone,
        length: OutputLength,
        formality: Formality,
        customInstruction: String,
        onDelta: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        let prepared = try TransformRequestBuilder.makeRequest(
            selectedText: selectedText,
            action: action,
            targetLanguage: targetLanguage,
            tone: tone,
            length: length,
            formality: formality,
            customInstruction: customInstruction,
            profiles: profiles,
            templates: templates
        )
        let profile = prepared.profile
        let keychain = KeychainStore(accessGroup: KeychainAccessGroup.current())
        let apiKey = try await keychain.load(service: SecretSeeder.service, account: profile.id)
        guard let apiKey, !apiKey.isEmpty else {
            throw LLMProviderError.missingAPIKey
        }

        let response = try await HTTPProviderClient(profile: profile, apiKey: apiKey).complete(prepared.request, onDelta: onDelta)

        modelContext.insert(TransformHistory(
            providerID: profile.id,
            sourceExcerpt: TextExcerpt.make(selectedText),
            resultExcerpt: TextExcerpt.make(response.text),
            providerName: profile.name,
            model: response.model ?? profile.model,
            action: action,
            targetLanguage: action == .translate ? targetLanguage : nil,
            status: "success",
            promptTokens: response.promptTokens,
            completionTokens: response.completionTokens,
            totalTokens: response.totalTokens
        ))
        try? modelContext.save()
        return response.text
    }
}
