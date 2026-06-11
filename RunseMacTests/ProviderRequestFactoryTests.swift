import RunseCore
import XCTest

@MainActor
final class ProviderRequestFactoryTests: XCTestCase {
    func testOpenAICompatibleRequestUsesProfileEndpointAndHeaders() throws {
        let profile = ProviderProfile(
            name: "Test",
            kind: .openAICompatible,
            baseURL: "https://api.example.com/",
            chatEndpoint: "v1/chat/completions",
            model: "test-model",
            extraHeadersJSON: #"{"X-Test":"yes"}"#
        )
        let request = LLMRequest(
            action: .refine,
            model: profile.model,
            systemPrompt: "System",
            userPrompt: "User"
        )

        let urlRequest = try ProviderRequestFactory.urlRequest(profile: profile, apiKey: "secret", request: request)
        let body = try XCTUnwrap(urlRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Test"), "yes")
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertNil(json["max_tokens"])
        XCTAssertEqual(messages.first?["content"], "System")
        XCTAssertEqual(messages.last?["content"], "User")
    }

    func testOpenAICompatibleRequestIncludesExplicitMaxTokensOnlyWhenSet() throws {
        let profile = ProviderProfile(
            name: "Test",
            kind: .openAICompatible,
            baseURL: "https://api.example.com",
            chatEndpoint: "/v1/chat/completions",
            model: "test-model"
        )
        let request = LLMRequest(
            action: .refine,
            model: profile.model,
            systemPrompt: "System",
            userPrompt: "User",
            maxTokens: 123
        )

        let body = ProviderRequestFactory.body(profile: profile, request: request)

        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 123)
    }

    func testParsesOpenAICompatibleResponseUsage() throws {
        let data = Data("""
        {
          "id": "response-id",
          "model": "test-model",
          "choices": [
            { "message": { "content": "Done" } }
          ],
          "usage": {
            "prompt_tokens": 3,
            "completion_tokens": 2,
            "total_tokens": 5
          }
        }
        """.utf8)

        let response = try ProviderResponseParser.parse(data: data, kind: .openAICompatible)

        XCTAssertEqual(response.text, "Done")
        XCTAssertEqual(response.responseID, "response-id")
        XCTAssertEqual(response.model, "test-model")
        XCTAssertEqual(response.promptTokens, 3)
        XCTAssertEqual(response.completionTokens, 2)
        XCTAssertEqual(response.totalTokens, 5)
    }

    func testParsesOpenAICompatibleStreamResponse() throws {
        let lines = [
            #"data: {"id":"response-id","model":"test-model","choices":[{"delta":{"content":"Hel"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"lo"}}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}"#,
            "data: [DONE]"
        ]

        let response = try XCTUnwrap(ProviderResponseParser.parseStream(lines: lines, kind: .openAICompatible))

        XCTAssertEqual(response.text, "Hello")
        XCTAssertEqual(response.responseID, "response-id")
        XCTAssertEqual(response.model, "test-model")
        XCTAssertEqual(response.promptTokens, 3)
        XCTAssertEqual(response.completionTokens, 2)
        XCTAssertEqual(response.totalTokens, 5)
    }

    func testStreamDeltasKeepWordBoundaryWhitespace() throws {
        let lines = [
            #"data: {"choices":[{"delta":{"content":"We"}}]}"#,
            #"data: {"choices":[{"delta":{"content":" were"}}]}"#,
            #"data: {"choices":[{"delta":{"content":" thinking.\n"}}]}"#,
            "data: [DONE]"
        ]

        let response = try XCTUnwrap(ProviderResponseParser.parseStream(lines: lines, kind: .openAICompatible))
        XCTAssertEqual(response.text, "We were thinking.")

        let partial = ProviderResponseParser.accumulatedText(lines: lines, kind: .openAICompatible)
        XCTAssertEqual(partial, "We were thinking.")
    }

    func testStreamStripsThinkBlockSpanningDeltas() throws {
        let lines = [
            #"data: {"choices":[{"delta":{"content":"<th"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"ink>planning"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"</think>An"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"swer"}}]}"#,
            "data: [DONE]"
        ]

        let response = try XCTUnwrap(ProviderResponseParser.parseStream(lines: lines, kind: .openAICompatible))
        XCTAssertEqual(response.text, "Answer")
    }
}
