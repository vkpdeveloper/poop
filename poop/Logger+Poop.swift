
import OSLog

// Centralised loggers — visible in Xcode Debug Console and Console.app
// Subsystem: bundle ID  |  Category: feature area
extension Logger {
    private static let subsystem = "com.ordinity.poop"

    /// LLM API calls — request/response lifecycle
    static let llm         = Logger(subsystem: subsystem, category: "LLM")

    /// Global hotkey intercept events
    static let hotkey      = Logger(subsystem: subsystem, category: "Hotkey")

    /// Clipboard read/write and key simulation
    static let clipboard   = Logger(subsystem: subsystem, category: "Clipboard")

    /// Accessibility permission checks
    static let accessibility = Logger(subsystem: subsystem, category: "Accessibility")

    /// App lifecycle
    static let app         = Logger(subsystem: subsystem, category: "App")
}
