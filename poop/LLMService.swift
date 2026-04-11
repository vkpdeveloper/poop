
import Foundation
import OSLog

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidURL(String)
    case networkError(String)
    case emptyResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is not set. Open Settings (⌘,) to add one."
        case .invalidURL(let url):
            return "Invalid API URL: \(url)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .emptyResponse:
            return "The API returned an empty response."
        case .apiError(let code, let msg):
            return "API error \(code): \(msg)"
        }
    }
}

class LLMService {
    static let shared = LLMService()
    private init() {}

    private func stripThinkBlocks(from text: String) -> String {
        let pattern = #"<think\b[^>]*>.*?</think>"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private func sanitizeResponseContent(_ content: String, isGroqProvider: Bool) -> String {
        let withoutThinkBlocks = isGroqProvider ? stripThinkBlocks(from: content) : content
        return withoutThinkBlocks.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    func correctGrammar(_ text: String) async throws -> String {
        let settings = SettingsManager.shared

        Logger.llm.info("▶ correctGrammar — \(text.count) chars, model: \(settings.modelName)")

        // Local providers (Ollama, LM Studio) don't require an API key.
        guard !settings.apiKey.isEmpty || !settings.selectedProvider.requiresAPIKey else {
            Logger.llm.error("✗ API key is empty")
            throw LLMError.missingAPIKey
        }

        let base = settings.apiBaseURL.hasSuffix("/")
            ? String(settings.apiBaseURL.dropLast())
            : settings.apiBaseURL
        let urlString = "\(base)/chat/completions"

        guard let requestURL = URL(string: urlString) else {
            Logger.llm.error("✗ Invalid URL: \(urlString)")
            throw LLMError.invalidURL(urlString)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Only set Authorization for providers that require an API key
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        // OpenRouter attribution headers (optional but recommended by their docs)
        request.setValue("https://github.com/poop-app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Poop",                         forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 30

        // stream: false — single non-streaming call, full response in one shot
        let body: [String: Any] = [
            "model":    settings.modelName,
            "stream":   false,
            "messages": [
                ["role": "system", "content": settings.systemPrompt],
                ["role": "user",   "content": text]
            ],
            "temperature": 0.3,
            "max_tokens":  2048,
            "reasoning_effort": "none",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.llm.debug("→ POST \(urlString)")
        if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
            Logger.llm.debug("→ request body: \(bodyStr)")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Logger.llm.error("✗ Network error: \(error.localizedDescription)")
            throw LLMError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            Logger.llm.error("✗ Unexpected response type")
            throw LLMError.networkError("Unexpected response type")
        }

        let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        Logger.llm.debug("← HTTP \(http.statusCode)")
        Logger.llm.debug("← response body: \(rawBody)")

        guard http.statusCode == 200 else {
            Logger.llm.error("✗ API error \(http.statusCode): \(rawBody)")
            throw LLMError.apiError(http.statusCode, rawBody)
        }

        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first   = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String,
            !content.isEmpty
        else {
            Logger.llm.error("✗ Could not parse response: \(rawBody)")
            throw LLMError.emptyResponse
        }

        let result = sanitizeResponseContent(content, isGroqProvider: settings.selectedProvider == .groq)

        guard !result.isEmpty else {
            Logger.llm.error("✗ Response became empty after sanitization")
            throw LLMError.emptyResponse
        }

        Logger.llm.info("✓ Got corrected text (\(result.count) chars)")
        return result
    }
}
