
import Foundation
import OSLog

// MARK: - STT Setup State

enum STTSetupState: Equatable {
    case unknown          // Not yet checked
    case notSetup         // parakeet-mlx CLI or model not present
    case settingUp        // Running uv tool install
    case downloadingModel // First run / model download in progress
    case ready            // Binary + model cache present
    case error(String)    // Unrecoverable
}

// MARK: - SpeechToTextService

/// Uses `uv tool install parakeet-mlx` to get the CLI, then invokes it via
/// `uv tool run parakeet-mlx` for transcription. Routing through uv ensures we
/// always use the managed installation — never a stale script left over from a
/// prior manual setup.
@Observable
class SpeechToTextService {
    static let shared = SpeechToTextService()

    // MARK: - Observable state

    var setupState: STTSetupState = .unknown
    var setupProgress: String = ""       // Latest status line (one-liner)
    var setupLog: [String] = []          // Accumulated clean log lines for the UI

    // MARK: - Cached uv path

    private var uvPath: String?

    private static let modelID = "mlx-community/parakeet-tdt-0.6b-v3"

    private init() {}

    // MARK: - uv discovery

    private static func findUV() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/uv",
            "/usr/local/bin/uv",
            "/opt/homebrew/bin/uv",
            "\(home)/.cargo/bin/uv",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Build a PATH that includes Homebrew/local bins so parakeet-mlx can find
    /// `ffmpeg` etc. Apps launched from Finder have a minimal launchd PATH.
    private static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extras = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
        ]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        let merged   = (extras + existing).reduce(into: [String]()) { acc, p in
            if !p.isEmpty, !acc.contains(p) { acc.append(p) }
        }
        env["PATH"] = merged.joined(separator: ":")
        if env["HOME"] == nil { env["HOME"] = home }
        return env
    }

    // MARK: - parakeet-mlx install check

    /// Returns true if `uv tool list` reports parakeet-mlx as installed.
    private static func isParakeetInstalled(uv: String) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: uv)
                proc.arguments     = ["tool", "list"]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError  = Pipe()
                guard (try? proc.run()) != nil else { cont.resume(returning: false); return }
                proc.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                cont.resume(returning: out.lowercased().contains("parakeet-mlx"))
            }
        }
    }

    // MARK: - Model cache detection

    private static func isModelCached() -> Bool {
        let home = NSHomeDirectory()
        let dir  = "\(home)/.cache/huggingface/hub/models--mlx-community--parakeet-tdt-0.6b-v3/snapshots"
        return FileManager.default.fileExists(atPath: dir)
    }

    // MARK: - Public API

    /// Called at launch to determine initial state without blocking.
    @MainActor
    func checkReadiness() {
        guard setupState == .unknown else { return }

        guard let uv = Self.findUV() else {
            setupState = .error("uv not found. Install uv (https://astral.sh/uv) to enable voice dictation.")
            return
        }
        uvPath = uv

        // Check install state async so we don't block the main thread at launch.
        Task {
            let installed = await Self.isParakeetInstalled(uv: uv)
            await MainActor.run {
                if installed && Self.isModelCached() {
                    setupState = .ready
                } else {
                    setupState = .notSetup
                }
            }
        }
    }

    /// Full setup: install CLI via uv, then download the model.
    @MainActor
    func setupAndDownload() async {
        guard ![.ready, .settingUp, .downloadingModel].contains(setupState) else { return }

        setupLog      = []
        setupProgress = ""

        guard let uv = uvPath ?? Self.findUV() else {
            setupState = .error("uv not found. Install uv from https://astral.sh/uv and try again.")
            return
        }
        uvPath = uv

        // ── Step 1: uv tool install parakeet-mlx -U ───────────────────────────
        setupState    = .settingUp
        setupProgress = "Installing parakeet-mlx via uv…"

        do {
            _ = try await runStreaming(
                uv,
                args: ["tool", "install", "parakeet-mlx", "-U"],
                timeout: 300
            ) { [weak self] line in
                Task { @MainActor [weak self] in self?.appendLog(line) }
            }
            Logger.stt.info("uv tool install parakeet-mlx succeeded")
        } catch {
            setupState = .error(error.localizedDescription)
            return
        }

        // ── Verify install ────────────────────────────────────────────────────
        guard await Self.isParakeetInstalled(uv: uv) else {
            setupState = .error(
                "parakeet-mlx was not found after installation. " +
                "Run 'uv tool list' in Terminal to diagnose, then retry."
            )
            return
        }
        Logger.stt.info("parakeet-mlx confirmed installed via uv tool list")

        // ── Step 2: Warm up — triggers model download ─────────────────────────
        setupState    = .downloadingModel
        setupProgress = "Downloading Parakeet model (~600 MB)…"

        let silentWAV = FileManager.default.temporaryDirectory
            .appendingPathComponent("poop_warmup_silence.wav")
        let warmupOut = FileManager.default.temporaryDirectory
            .appendingPathComponent("poop_warmup_out_\(UUID().uuidString)")
        writeSilentWAV(to: silentWAV)
        try? FileManager.default.createDirectory(at: warmupOut, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: silentWAV)
            try? FileManager.default.removeItem(at: warmupOut)
        }

        do {
            _ = try await runStreaming(
                uv,
                args: [
                    "tool", "run", "parakeet-mlx",
                    silentWAV.path,
                    "--model", Self.modelID,
                    "--output-format", "txt",
                    "--output-dir", warmupOut.path,
                ],
                timeout: 900   // allow up to 15 min on slow connections
            ) { [weak self] line in
                Task { @MainActor [weak self] in self?.appendLog(line) }
            }
        } catch {
            // parakeet-mlx may exit non-zero for silent audio (nothing to transcribe)
            // but the model is still downloaded — treat as success if cache exists.
            if !Self.isModelCached() {
                setupState = .error(error.localizedDescription)
                return
            }
            Logger.stt.info("Warmup exited non-zero but model is cached — treating as success")
        }

        setupState    = .ready
        setupProgress = ""
        setupLog      = []
        Logger.stt.info("STT ready — parakeet-mlx + model available")
    }

    /// Transcribe audio at `audioURL`. Returns the plain-text transcript.
    func transcribe(audioURL: URL) async throws -> String {
        guard let uv = uvPath else {
            throw STTError.notReady
        }

        // Pre-flight: file exists and is non-trivial.
        let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        let size  = (attrs?[.size] as? Int) ?? 0
        Logger.stt.info("Audio file size: \(size) bytes")
        guard size > 1024 else {
            throw STTError.audioInvalid("Recording file is empty or truncated (\(size) bytes).")
        }
        // Sanity-check WAV header (RIFF…WAVE).
        if let fh = try? FileHandle(forReadingFrom: audioURL) {
            defer { try? fh.close() }
            let head = (try? fh.read(upToCount: 12)) ?? Data()
            let isRIFF = head.count == 12
                && head[0..<4] == Data("RIFF".utf8)
                && head[8..<12] == Data("WAVE".utf8)
            if !isRIFF {
                Logger.stt.warning("WAV header check failed; first 12 bytes: \(head as NSData)")
            }
        }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("poop_stt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        // DEBUG: keep output dir so we can inspect the .txt file
        // defer { try? FileManager.default.removeItem(at: outputDir) }
        Logger.stt.info("Output dir: \(outputDir.path)")

        Logger.stt.info("Transcribing \(audioURL.lastPathComponent)")

        // Route through `uv tool run` so we always use the managed installation,
        // never a stale script that might have been left at ~/.local/bin/parakeet-mlx.
        let cliOutput = try await run(
            uv,
            args: [
                "tool", "run", "parakeet-mlx",
                audioURL.path,
                "--model", Self.modelID,
                "--output-format", "txt",
                "--output-dir", outputDir.path,
            ],
            timeout: 120
        )

        // parakeet-mlx logs transcription failures to stdout and exits 0
        // (e.g. "Error transcribing file …: FFmpeg is not installed…").
        // Detect that and surface it instead of letting the empty dir confuse us.
        if cliOutput.lowercased().contains("error transcribing") {
            let line = cliOutput
                .components(separatedBy: .newlines)
                .first(where: { $0.lowercased().contains("error transcribing") })
                ?? cliOutput
            throw STTError.processFailed(
                executable: "parakeet-mlx",
                status: 0,
                output: line.trimmingCharacters(in: .whitespaces)
            )
        }

        // parakeet-mlx names the output file after the input stem (default --output-template).
        // Try the expected name first; fall back to scanning the dir in case naming changes.
        let expectedName = audioURL.deletingPathExtension().lastPathComponent + ".txt"
        let expectedURL  = outputDir.appendingPathComponent(expectedName)

        let txtURL: URL
        if FileManager.default.fileExists(atPath: expectedURL.path) {
            txtURL = expectedURL
        } else {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: outputDir, includingPropertiesForKeys: nil
            )) ?? []
            guard let found = contents.first(where: { $0.pathExtension == "txt" }) else {
                let listing = contents.map(\.lastPathComponent).joined(separator: ", ")
                Logger.stt.error("No .txt output in \(outputDir.path). Dir contents: [\(listing)]")
                throw STTError.noOutputFile(listing.isEmpty ? "(empty)" : listing)
            }
            Logger.stt.warning("Expected \(expectedName), found \(found.lastPathComponent)")
            txtURL = found
        }

        let raw = (try? String(contentsOf: txtURL, encoding: .utf8)) ?? ""
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.stt.info("Transcript: \(text.count) chars")
        return text
    }

    // MARK: - Log helpers

    @MainActor
    private func appendLog(_ raw: String) {
        let clean = stripANSI(raw)
        guard !clean.isEmpty else { return }
        setupLog.append(clean)
        setupProgress = clean
        Logger.stt.debug("[stt] \(clean)")
    }

    // Strips ANSI escape sequences (used by tqdm progress bars etc.)
    private func stripANSI(_ s: String) -> String {
        var result = s
        if let regex = try? NSRegularExpression(pattern: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // Carriage-return tricks (overwrite-style progress): keep last segment
        if result.contains("\r") {
            result = result.components(separatedBy: "\r").last ?? result
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Silent WAV writer

    /// Writes a 0.5-second 16 kHz mono 16-bit PCM WAV of silence.
    private func writeSilentWAV(to url: URL) {
        let sampleRate:    UInt32 = 16_000
        let numSamples:    UInt32 = sampleRate / 2   // 0.5 s
        let numChannels:   UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate   = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize   = numSamples * UInt32(blockAlign)

        var wav = Data()
        func le<T: FixedWidthInteger>(_ v: T) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: "RIFF".utf8); le(UInt32(36 + dataSize))
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8); le(UInt32(16))
        le(UInt16(1)); le(numChannels); le(sampleRate); le(byteRate); le(blockAlign); le(bitsPerSample)
        wav.append(contentsOf: "data".utf8); le(dataSize)
        wav.append(Data(count: Int(dataSize)))   // silence
        try? wav.write(to: url)
    }

    // MARK: - Subprocess runner (blocking, returns all stdout)

    @discardableResult
    private func run(
        _ executable: String,
        args: [String],
        timeout: TimeInterval = 60
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments     = args
                proc.environment   = Self.childEnvironment()
                let out = Pipe(), err = Pipe()
                proc.standardOutput = out
                proc.standardError  = err
                do    { try proc.run() }
                catch { continuation.resume(throwing: error); return }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if proc.isRunning { proc.terminate() }
                }
                proc.waitUntilExit()
                let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus != 0 {
                    let msg = stderr.isEmpty ? stdout : stderr
                    continuation.resume(throwing: STTError.processFailed(
                        executable: (executable as NSString).lastPathComponent,
                        status: Int(proc.terminationStatus),
                        output: msg.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } else {
                    continuation.resume(returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    // MARK: - Subprocess runner (streaming — calls onLine for each output line)

    @discardableResult
    private func runStreaming(
        _ executable: String,
        args: [String],
        timeout: TimeInterval = 300,
        onLine: @escaping (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments     = args
                proc.environment   = Self.childEnvironment()

                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError  = errPipe

                let lock      = NSLock()
                var allOutput = ""

                func handle(_ data: Data) {
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }
                    lock.withLock { allOutput += text }
                    for segment in text.components(separatedBy: .newlines) {
                        let t = segment.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { onLine(t) }
                    }
                }

                outPipe.fileHandleForReading.readabilityHandler = { handle($0.availableData) }
                errPipe.fileHandleForReading.readabilityHandler = { handle($0.availableData) }

                do    { try proc.run() }
                catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if proc.isRunning { proc.terminate() }
                }
                proc.waitUntilExit()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil

                handle(outPipe.fileHandleForReading.readDataToEndOfFile())
                handle(errPipe.fileHandleForReading.readDataToEndOfFile())

                if proc.terminationStatus != 0 {
                    let output = lock.withLock { allOutput }
                    continuation.resume(throwing: STTError.processFailed(
                        executable: (executable as NSString).lastPathComponent,
                        status: Int(proc.terminationStatus),
                        output: output.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } else {
                    let output = lock.withLock { allOutput }
                    continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }
}

// MARK: - NSLock convenience

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }; return body()
    }
}

// MARK: - Errors

enum STTError: LocalizedError {
    case notReady
    case processFailed(executable: String, status: Int, output: String)
    case noOutputFile(String)
    case audioInvalid(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Voice dictation is not set up. Please visit Settings → Voice Dictation and click \"Set Up\"."
        case let .processFailed(exe, status, output):
            let tail = output.suffix(800)
            return "\(exe) failed (exit \(status)): \(tail.isEmpty ? "no output" : String(tail))"
        case let .noOutputFile(listing):
            return "Transcription finished but no .txt was produced. Output dir: [\(listing)]"
        case let .audioInvalid(msg):
            return "Audio invalid: \(msg)"
        }
    }
}
