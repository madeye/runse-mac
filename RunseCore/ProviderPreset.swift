import Foundation

/// Predefined provider configurations so users only need to fill in an API key.
///
/// Mirrors the iOS `ProviderPreset` enum in the sibling `runse` repo so the two
/// apps offer the same catalog. The `custom` case carries no configuration —
/// it's the fall-through that lets users enter every field manually.
public enum ProviderPreset: String, CaseIterable, Identifiable, Sendable {
    case deepSeek
    case kimi
    case miniMax
    case glm
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .custom: String(localized: "Custom", bundle: .runseCore)
        case .deepSeek: "DeepSeek China"
        case .kimi: "Kimi China"
        case .miniMax: "MiniMax China"
        case .glm: "GLM China"
        }
    }

    public struct Configuration: Sendable, Equatable {
        public let name: String
        public let kind: ProviderKind
        public let baseURL: String
        public let endpoint: String
        public let model: String
        public let extraHeaders: String

        public init(name: String, kind: ProviderKind, baseURL: String, endpoint: String, model: String, extraHeaders: String = "{}") {
            self.name = name
            self.kind = kind
            self.baseURL = baseURL
            self.endpoint = endpoint
            self.model = model
            self.extraHeaders = extraHeaders
        }
    }

    public var configuration: Configuration? {
        switch self {
        case .custom:
            nil
        case .deepSeek:
            Configuration(
                name: "DeepSeek China",
                kind: .openAICompatible,
                baseURL: "https://api.deepseek.com",
                endpoint: "/chat/completions",
                model: "deepseek-v4-flash"
            )
        case .kimi:
            Configuration(
                name: "Kimi China",
                kind: .openAICompatible,
                baseURL: "https://api.moonshot.cn/v1",
                endpoint: "/chat/completions",
                model: "kimi-k2.5"
            )
        case .miniMax:
            Configuration(
                name: "MiniMax China",
                kind: .openAICompatible,
                baseURL: "https://api.minimaxi.com/v1",
                endpoint: "/chat/completions",
                model: "MiniMax-M2.5"
            )
        case .glm:
            Configuration(
                name: "GLM China",
                kind: .openAICompatible,
                baseURL: "https://open.bigmodel.cn/api/paas/v4",
                endpoint: "/chat/completions",
                model: "glm-5"
            )
        }
    }

    /// Names that the editor treats as "auto-managed" — switching presets is
    /// allowed to overwrite the name field when it currently holds one of
    /// these (or is empty).
    public static var allPresetNames: Set<String> {
        Set(allCases.compactMap(\.configuration?.name))
    }

    /// Best-effort match of an existing profile to a known preset by base URL
    /// + model. Returns `.custom` when nothing matches.
    public static func infer(from profile: ProviderProfile?) -> ProviderPreset {
        guard let profile else { return .custom }
        let normalizedBaseURL = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return allCases.first {
            guard let configuration = $0.configuration else { return false }
            return configuration.baseURL == normalizedBaseURL && configuration.model == profile.model
        } ?? .custom
    }
}
