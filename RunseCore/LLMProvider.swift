import Foundation

public struct LLMRequest: Sendable, Equatable {
    public var action: TransformAction
    public var model: String
    public var systemPrompt: String
    public var userPrompt: String
    public var temperature: Double
    public var maxTokens: Int?

    public init(action: TransformAction, model: String, systemPrompt: String, userPrompt: String, temperature: Double = 0.2, maxTokens: Int? = nil) {
        self.action = action
        self.model = model
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct LLMResponse: Sendable, Equatable {
    public var text: String
    public var responseID: String?
    public var model: String?
    public var usage: [String: Int]

    public var promptTokens: Int {
        usage["prompt_tokens"] ?? usage["input_tokens"] ?? 0
    }

    public var completionTokens: Int {
        usage["completion_tokens"] ?? usage["output_tokens"] ?? 0
    }

    public var totalTokens: Int {
        usage["total_tokens"] ?? (promptTokens + completionTokens)
    }

    public init(text: String, responseID: String? = nil, model: String? = nil, usage: [String: Int] = [:]) {
        self.text = text
        self.responseID = responseID
        self.model = model
        self.usage = usage
    }
}

public enum LLMProviderError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case timeout
    case invalidStatus(Int, String)
    case malformedJSON
    /// Provider returned a 2xx response, but no usable text content was
    /// extractable. The associated value carries a short raw-body excerpt to
    /// help diagnose reasoning-model schema variants (e.g. content split
    /// across `reasoning_content` vs `content`, or `<think>…</think>` blocks
    /// truncated before the final answer.
    case emptyOutput(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Missing API key."
        case .invalidURL: "Invalid provider URL."
        case .timeout: "The provider request timed out."
        case .invalidStatus(let code, let body): "Provider returned HTTP \(code): \(body)"
        case .malformedJSON: "The provider response was malformed."
        case .emptyOutput(let snippet):
            "The provider returned an empty result. Raw: \(snippet)"
        }
    }
}

public protocol LLMProviderClient {
    @MainActor func complete(_ request: LLMRequest, onDelta: (@MainActor (String) -> Void)?) async throws -> LLMResponse
}

extension LLMProviderClient {
    @MainActor public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try await complete(request, onDelta: nil)
    }
}

public final class HTTPProviderClient: LLMProviderClient {
    private let profile: ProviderProfile
    private let apiKey: String
    private let session: URLSession

    public init(profile: ProviderProfile, apiKey: String, session: URLSession = .shared) {
        self.profile = profile
        self.apiKey = apiKey
        self.session = session
    }

    @MainActor public func complete(_ request: LLMRequest, onDelta: (@MainActor (String) -> Void)? = nil) async throws -> LLMResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.missingAPIKey
        }
        let urlRequest = try ProviderRequestFactory.urlRequest(profile: profile, apiKey: apiKey, request: request)
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw LLMProviderError.malformedJSON }
            var data = Data()
            var lines: [String] = []
            for try await line in bytes.lines {
                lines.append(line)
                data.append(contentsOf: line.utf8)
                data.append(0x0A)
                if let onDelta, line.hasPrefix("data:") {
                    let partial = ProviderResponseParser.accumulatedText(lines: lines, kind: profile.kind)
                    if !partial.isEmpty {
                        onDelta(partial)
                    }
                }
            }
            guard (200..<300).contains(http.statusCode) else {
                throw LLMProviderError.invalidStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            if let streamResponse = try ProviderResponseParser.parseStream(lines: lines, kind: profile.kind) {
                return streamResponse
            }
            return try ProviderResponseParser.parse(data: data, kind: profile.kind)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMProviderError.timeout
        }
    }
}

public struct ProviderAPITestResult: Sendable, Equatable {
    public var message: String
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int

    public init(message: String, promptTokens: Int = 0, completionTokens: Int = 0, totalTokens: Int = 0) {
        self.message = message
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public enum ProviderAPITester {
    @MainActor public static func test(profile: ProviderProfile, apiKey: String) async throws -> ProviderAPITestResult {
        let request = LLMRequest(
            action: .refine,
            model: profile.model,
            systemPrompt: "You are an API connectivity test. Reply with OK only.",
            userPrompt: "Reply with OK.",
            temperature: 0
        )
        let response = try await HTTPProviderClient(profile: profile, apiKey: apiKey).complete(request)
        return ProviderAPITestResult(
            message: response.text,
            promptTokens: response.promptTokens,
            completionTokens: response.completionTokens,
            totalTokens: response.totalTokens
        )
    }
}

public enum ProviderRequestFactory {
    public static func urlRequest(profile: ProviderProfile, apiKey: String, request: LLMRequest) throws -> URLRequest {
        let endpoint = endpointURL(profile: profile)
        guard let url = URL(string: endpoint) else { throw LLMProviderError.invalidURL }
        var urlRequest = URLRequest(url: url, timeoutInterval: 45)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (key, value) in extraHeaders(from: profile.extraHeadersJSON) {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(profile: profile, request: request), options: [])
        return urlRequest
    }

    public static func body(profile: ProviderProfile, request: LLMRequest) -> [String: Any] {
        switch profile.kind {
        case .openAIResponses:
            var body: [String: Any] = [
                "model": request.model,
                "input": [
                    ["role": "system", "content": request.systemPrompt],
                    ["role": "user", "content": request.userPrompt]
                ],
                "temperature": request.temperature,
                "stream": true
            ]
            if let maxTokens = request.maxTokens {
                body["max_output_tokens"] = maxTokens
            }
            return body
        case .anthropicMessages, .anthropicCompatible:
            var body: [String: Any] = [
                "model": request.model,
                "system": request.systemPrompt,
                "messages": [
                    ["role": "user", "content": request.userPrompt]
                ],
                "temperature": request.temperature,
                "stream": true
            ]
            if let maxTokens = request.maxTokens {
                body["max_tokens"] = maxTokens
            }
            return body
        case .openAICompatible:
            var body: [String: Any] = [
                "model": request.model,
                "messages": [
                    ["role": "system", "content": request.systemPrompt],
                    ["role": "user", "content": request.userPrompt]
                ],
                "temperature": request.temperature,
                "stream": true
            ]
            if let maxTokens = request.maxTokens {
                body["max_tokens"] = maxTokens
            }
            return body
        }
    }

    private static func endpointURL(profile: ProviderProfile) -> String {
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = profile.chatEndpoint.hasPrefix("/") ? profile.chatEndpoint : "/\(profile.chatEndpoint)"
        return "\(base)\(endpoint)"
    }

    private static func extraHeaders(from json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return object
    }
}

public enum ProviderResponseParser {
    public static func accumulatedText(lines: [String], kind: ProviderKind) -> String {
        var textParts: [String] = []
        var reasoningParts: [String] = []
        for line in lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch kind {
            case .openAIResponses:
                appendResponsesStreamText(from: object, to: &textParts)
            case .openAICompatible:
                appendChatCompletionStreamText(from: object, textParts: &textParts, reasoningParts: &reasoningParts)
            case .anthropicMessages, .anthropicCompatible:
                appendAnthropicStreamText(from: object, to: &textParts)
            }
        }
        let text = textParts.joined()
        return text.isEmpty ? reasoningParts.joined() : text
    }

    public static func parse(data: Data, kind: ProviderKind) throws -> LLMResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.malformedJSON
        }
        let text: String?
        switch kind {
        case .openAIResponses:
            text = parseResponsesText(object)
        case .openAICompatible:
            text = parseChatCompletionText(object)
        case .anthropicMessages, .anthropicCompatible:
            text = ((object["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n"))
        }
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw LLMProviderError.emptyOutput(rawSnippet(data))
        }
        return LLMResponse(text: value, responseID: object["id"] as? String, model: object["model"] as? String, usage: parseUsage(object["usage"] as? [String: Any]))
    }

    public static func parseStream(lines: [String], kind: ProviderKind) throws -> LLMResponse? {
        var textParts: [String] = []
        var reasoningParts: [String] = []
        var responseID: String?
        var model: String?
        var usage: [String: Int] = [:]
        var sawStreamData = false

        for line in lines {
            guard line.hasPrefix("data:") else { continue }
            sawStreamData = true

            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]", let data = payload.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LLMProviderError.malformedJSON
            }

            responseID = responseID ?? object["id"] as? String
            model = model ?? object["model"] as? String
            if let objectUsage = parseStreamUsage(object) {
                usage.merge(objectUsage) { _, new in new }
            }

            switch kind {
            case .openAIResponses:
                appendResponsesStreamText(from: object, to: &textParts)
            case .openAICompatible:
                appendChatCompletionStreamText(from: object, textParts: &textParts, reasoningParts: &reasoningParts)
            case .anthropicMessages, .anthropicCompatible:
                appendAnthropicStreamText(from: object, to: &textParts)
            }
        }

        guard sawStreamData else { return nil }
        let text = textParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoning = reasoningParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let value = text.isEmpty ? reasoning : text
        guard !value.isEmpty else {
            let raw = lines.joined(separator: "\n").data(using: .utf8) ?? Data()
            throw LLMProviderError.emptyOutput(rawSnippet(raw))
        }
        return LLMResponse(text: value, responseID: responseID, model: model, usage: usage)
    }

    /// Extracts an answer from a Chat Completions-shaped response, tolerating
    /// the schema variants used by NVIDIA NIM, DeepSeek, Kimi, and Qwen3
    /// thinking models. Order:
    ///   1. `choices[0].message.content`, with any `<think>…</think>` block
    ///      stripped (Qwen3 / DeepSeek-R1 thinking-mode answers).
    ///   2. The legacy completions field `choices[0].text`.
    ///   3. `choices[0].message.reasoning_content` — last resort, since this
    ///      is intended for the model's chain of thought, but is the only
    ///      non-empty field when a reasoning model gets cut off before
    ///      producing the final answer.
    static func parseChatCompletionText(_ object: [String: Any]) -> String? {
        guard let choice = (object["choices"] as? [[String: Any]])?.first else { return nil }
        let message = choice["message"] as? [String: Any]
        if let content = message?["content"] as? String,
           let stripped = stripThinkBlocks(content), !stripped.isEmpty {
            return stripped
        }
        if let legacyText = choice["text"] as? String, !legacyText.isEmpty {
            return legacyText
        }
        if let reasoning = message?["reasoning_content"] as? String, !reasoning.isEmpty {
            return reasoning
        }
        return nil
    }

    /// Removes `<think>…</think>` (and `<thinking>…</thinking>`) blocks that
    /// some reasoning models emit inline before their final answer. Returns
    /// the cleaned, trimmed text, or nil if the input was nil.
    static func stripThinkBlocks(_ raw: String) -> String? {
        var text = raw
        for tag in ["think", "thinking"] {
            // Greedy in tag, lazy in body — handles unclosed blocks (model
            // truncated mid-thought) by stripping from the opener to EOF.
            let pattern = "<\(tag)\\b[^>]*>[\\s\\S]*?(?:</\(tag)>|$)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseResponsesText(_ object: [String: Any]) -> String? {
        if let direct = object["output_text"] as? String { return direct }
        guard let output = object["output"] as? [[String: Any]] else { return nil }
        return output.compactMap { item in
            (item["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        }.joined(separator: "\n")
    }

    private static func appendResponsesStreamText(from object: [String: Any], to textParts: inout [String]) {
        if object["type"] as? String == "response.output_text.delta",
           let delta = object["delta"] as? String {
            textParts.append(delta)
            return
        }
        if let response = object["response"] as? [String: Any],
           let finalText = parseResponsesText(response),
           !finalText.isEmpty {
            textParts = [finalText]
        }
    }

    private static func appendChatCompletionStreamText(from object: [String: Any], textParts: inout [String], reasoningParts: inout [String]) {
        guard let choice = (object["choices"] as? [[String: Any]])?.first else { return }
        let delta = choice["delta"] as? [String: Any]
        let message = choice["message"] as? [String: Any]

        if let content = delta?["content"] as? String ?? message?["content"] as? String,
           let stripped = stripThinkBlocks(content),
           !stripped.isEmpty {
            textParts.append(stripped)
        }
        if let reasoning = delta?["reasoning_content"] as? String ?? message?["reasoning_content"] as? String,
           !reasoning.isEmpty {
            reasoningParts.append(reasoning)
        }
        if let legacyText = choice["text"] as? String, !legacyText.isEmpty {
            textParts.append(legacyText)
        }
    }

    private static func appendAnthropicStreamText(from object: [String: Any], to textParts: inout [String]) {
        if let delta = object["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            textParts.append(text)
            return
        }
        if let content = object["content"] as? [[String: Any]] {
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty {
                textParts = [text]
            }
        }
    }

    private static func rawSnippet(_ data: Data, limit: Int = 240) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    private static func parseStreamUsage(_ object: [String: Any]) -> [String: Int]? {
        let usage = parseUsage(object["usage"] as? [String: Any])
        if !usage.isEmpty {
            return usage
        }
        if let response = object["response"] as? [String: Any] {
            let responseUsage = parseUsage(response["usage"] as? [String: Any])
            if !responseUsage.isEmpty {
                return responseUsage
            }
        }
        if let message = object["message"] as? [String: Any] {
            let messageUsage = parseUsage(message["usage"] as? [String: Any])
            if !messageUsage.isEmpty {
                return messageUsage
            }
        }
        return nil
    }

    private static func parseUsage(_ usage: [String: Any]?) -> [String: Int] {
        usage?.reduce(into: [String: Int]()) { partial, item in
            if let value = item.value as? Int {
                partial[item.key] = value
            }
        } ?? [:]
    }
}
