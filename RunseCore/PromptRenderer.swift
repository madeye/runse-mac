import Foundation

public struct PromptContext: Sendable {
    public var selectedText: String
    public var action: TransformAction
    public var targetLanguage: String
    public var tone: Tone
    public var length: OutputLength
    public var formality: Formality
    public var outputLocale: String
    public var customInstruction: String

    public init(
        selectedText: String,
        action: TransformAction,
        targetLanguage: String = RunseConstants.defaultTranslationLanguage,
        tone: Tone = .natural,
        length: OutputLength = .same,
        formality: Formality = .neutral,
        outputLocale: String = "same as input",
        customInstruction: String = ""
    ) {
        self.selectedText = selectedText
        self.action = action
        self.targetLanguage = targetLanguage
        self.tone = tone
        self.length = length
        self.formality = formality
        self.outputLocale = outputLocale
        self.customInstruction = customInstruction
    }
}

public struct RenderedPrompt: Equatable, Sendable {
    public var system: String
    public var user: String
}

public enum PromptRenderer {
    public static func render(template: PromptTemplate, context: PromptContext) -> RenderedPrompt {
        let variables = [
            "selected_text": context.selectedText,
            "action": context.action.rawValue,
            "target_language": context.targetLanguage,
            "tone": context.tone.rawValue,
            "length": context.length.rawValue,
            "formality": context.formality.rawValue,
            "output_locale": context.outputLocale,
            "custom_instruction": context.customInstruction
        ]
        return RenderedPrompt(
            system: replace(in: template.systemTemplate, variables: variables),
            user: replace(in: template.userTemplate, variables: variables)
        )
    }

    private static func replace(in template: String, variables: [String: String]) -> String {
        variables.reduce(template) { partial, item in
            partial.replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
        }
    }
}
