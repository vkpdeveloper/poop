
import Foundation
import CoreGraphics

// MARK: - LLM Provider

enum LLMProvider: String, CaseIterable, Identifiable {
    case openAI      = "openai"
    case openRouter  = "openrouter"
    case anthropic   = "anthropic"
    case groq        = "groq"
    case ollama      = "ollama"
    case lmStudio    = "lmstudio"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:     return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .anthropic:  return "Anthropic"
        case .groq:       return "Groq"
        case .ollama:     return "Ollama"
        case .lmStudio:   return "LM Studio"
        }
    }

    var icon: String {
        switch self {
        case .openAI:     return "brain"
        case .openRouter: return "arrow.triangle.branch"
        case .anthropic:  return "sparkles"
        case .groq:       return "bolt.fill"
        case .ollama:     return "terminal"
        case .lmStudio:   return "laptopcomputer"
        }
    }

    /// Fixed base URL. nil = local provider that needs a custom host.
    var fixedBaseURL: String? {
        switch self {
        case .openAI:     return "https://api.openai.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .anthropic:  return "https://api.anthropic.com/v1"
        case .groq:       return "https://api.groq.com/openai/v1"
        case .ollama:     return nil
        case .lmStudio:   return nil
        }
    }

    /// Default host for local providers (user can change the host).
    var defaultHost: String {
        switch self {
        case .ollama:   return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234"
        default:        return ""
        }
    }

    /// Whether the user can edit the base URL (OpenAI/Anthropic: yes; others: no).
    var showsBaseURLField: Bool {
        switch self {
        case .openAI, .anthropic: return true
        default: return false
        }
    }

    /// Whether to show the host input (local providers only).
    var isLocal: Bool { self == .ollama || self == .lmStudio }

    /// Local providers don't need an API key.
    var requiresAPIKey: Bool { !isLocal }

    var defaultModel: String {
        switch self {
        case .openAI:     return "gpt-4o-mini"
        case .openRouter: return "openai/gpt-4o-mini"
        case .anthropic:  return "claude-3-5-haiku-20241022"
        case .groq:       return "llama-3.1-8b-instant"
        case .ollama:     return "llama3.2"
        case .lmStudio:   return "local-model"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openAI:     return "sk-…"
        case .openRouter: return "sk-or-…"
        case .anthropic:  return "sk-ant-…"
        case .groq:       return "gsk_…"
        default:          return ""
        }
    }
}

// MARK: - Settings Manager

// Plain UserDefaults-backed settings store.
// SwiftUI views access settings directly via @AppStorage.
// The service layer reads from this singleton.
class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard

    private init() {
        // Run prompt migration eagerly at startup so the correct value is
        // already in UserDefaults before @AppStorage reads it. If the migration
        // were deferred to the systemPrompt getter, @AppStorage would read the
        // stale/empty value first and skip the getter entirely.
        migrateSystemPromptIfNeeded()
    }

    // MARK: - Private

    private func migrateSystemPromptIfNeeded() {
        let stored = defaults.string(forKey: "systemPrompt") ?? ""
        let version = defaults.integer(forKey: "systemPromptVersion")
        if stored.isEmpty || version < Self.currentPromptVersion {
            defaults.set(Self.defaultSystemPrompt, forKey: "systemPrompt")
            defaults.set(Self.currentPromptVersion, forKey: "systemPromptVersion")
        }
    }

    // MARK: - Provider

    var selectedProvider: LLMProvider {
        get {
            guard let raw = defaults.string(forKey: "selectedProvider"),
                  let provider = LLMProvider(rawValue: raw) else {
                return .openRouter
            }
            return provider
        }
        set { defaults.set(newValue.rawValue, forKey: "selectedProvider") }
    }

    /// Custom host for local providers (Ollama, LM Studio).
    var customHost: String {
        get { defaults.string(forKey: "customHost") ?? "" }
        set { defaults.set(newValue, forKey: "customHost") }
    }

    // MARK: - API

    /// Whether the floating corner indicator is shown during processing.
    var showFloatingIndicator: Bool {
        get { defaults.object(forKey: "showFloatingIndicator") != nil
                ? defaults.bool(forKey: "showFloatingIndicator")
                : true  // on by default
        }
        set { defaults.set(newValue, forKey: "showFloatingIndicator") }
    }

    var apiBaseURL: String {
        get { defaults.string(forKey: "apiBaseURL") ?? "https://openrouter.ai/api/v1" }
        set { defaults.set(newValue, forKey: "apiBaseURL") }
    }

    var apiKey: String {
        get { defaults.string(forKey: "apiKey") ?? "" }
        set { defaults.set(newValue, forKey: "apiKey") }
    }

    var modelName: String {
        get { defaults.string(forKey: "modelName") ?? "openai/gpt-4o-mini" }
        set { defaults.set(newValue, forKey: "modelName") }
    }

    var systemPrompt: String {
        get { defaults.string(forKey: "systemPrompt") ?? Self.defaultSystemPrompt }
        set {
            defaults.set(newValue, forKey: "systemPrompt")
            defaults.set(Self.currentPromptVersion, forKey: "systemPromptVersion")
        }
    }

    // Bump this whenever the default prompt changes so existing installs auto-update
    static let currentPromptVersion = 2

    // MARK: - Hotkey

    // Hotkey — key code (macOS virtual key code, e.g. 3 = F)
    var hotkeyKeyCode: Int {
        get { defaults.object(forKey: "hotkeyKeyCode") != nil ? defaults.integer(forKey: "hotkeyKeyCode") : 3 }
        set { defaults.set(newValue, forKey: "hotkeyKeyCode") }
    }

    var hotkeyCommand: Bool {
        get { defaults.object(forKey: "hotkeyCommand") != nil ? defaults.bool(forKey: "hotkeyCommand") : true }
        set { defaults.set(newValue, forKey: "hotkeyCommand") }
    }

    var hotkeyShift: Bool {
        get { defaults.object(forKey: "hotkeyShift") != nil ? defaults.bool(forKey: "hotkeyShift") : true }
        set { defaults.set(newValue, forKey: "hotkeyShift") }
    }

    var hotkeyOption: Bool {
        get { defaults.bool(forKey: "hotkeyOption") }
        set { defaults.set(newValue, forKey: "hotkeyOption") }
    }

    var hotkeyControl: Bool {
        get { defaults.bool(forKey: "hotkeyControl") }
        set { defaults.set(newValue, forKey: "hotkeyControl") }
    }

    // CGEventFlags built from individual modifier booleans
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if hotkeyCommand { flags.insert(.maskCommand) }
        if hotkeyShift    { flags.insert(.maskShift) }
        if hotkeyOption   { flags.insert(.maskAlternate) }
        if hotkeyControl  { flags.insert(.maskControl) }
        return flags
    }

    // Human-readable shortcut string, e.g. "⌘⇧F"
    var displayString: String {
        var s = ""
        if hotkeyControl { s += "⌃" }
        if hotkeyOption  { s += "⌥" }
        if hotkeyShift   { s += "⇧" }
        if hotkeyCommand { s += "⌘" }
        s += keyCodeToChar(hotkeyKeyCode)
        return s
    }

    static let defaultSystemPrompt = """
You are a grammar and style corrector. Your ONLY job is to rewrite the text you receive with corrected grammar, spelling, and natural phrasing.

STRICT RULES — follow these without exception:
1. NEVER answer questions. If the input looks like a question, rewrite it as a grammatically correct question and return that. Do NOT provide an answer.
2. NEVER explain what you changed.
3. NEVER add commentary, notes, or context.
4. NEVER wrap output in quotes or markdown.
5. NEVER refuse or say you cannot do something.
6. Output ONLY the corrected version of the input text — nothing else.
7. Preserve the original meaning, tone, and length as much as possible.
8. If the input is already correct, return it unchanged.

Think of yourself as a silent spell-checker, not a chatbot. The input is raw text to be fixed, not a message to you.
"""

    // Maps macOS virtual key codes to display characters
    static let keyCodeMap: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
        37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    func keyCodeToChar(_ code: Int) -> String {
        SettingsManager.keyCodeMap[code] ?? "?"
    }
}
