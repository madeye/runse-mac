import Foundation
import RunseCore

enum TransformRequestBuilder {
    static func makeRequest(
        selectedText: String,
        action: TransformAction,
        targetLanguage: String,
        tone: Tone,
        length: OutputLength,
        formality: Formality,
        customInstruction: String,
        profiles: [ProviderProfile],
        templates: [PromptTemplate]
    ) throws -> (profile: ProviderProfile, request: LLMRequest) {
        guard let profile = profiles.first(where: \.isDefault) ?? profiles.first else {
            throw LLMProviderError.invalidURL
        }

        let template = templates.first { $0.action == action } ?? PromptTemplate.builtIns().first { $0.action == action }!
        let context = PromptContext(
            selectedText: selectedText,
            action: action,
            targetLanguage: targetLanguage,
            tone: tone,
            length: length,
            formality: formality,
            customInstruction: customInstruction
        )
        let prompt = PromptRenderer.render(template: template, context: context)
        let request = LLMRequest(
            action: action,
            model: profile.model,
            systemPrompt: prompt.system,
            userPrompt: prompt.user
        )
        return (profile, request)
    }
}
