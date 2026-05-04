
import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Sidebar Item

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, voice, trading, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:   "General"
        case .shortcuts: "Shortcuts"
        case .voice:     "Voice"
        case .trading:   "Trading"
        case .system:    "System"
        }
    }

    var icon: String {
        switch self {
        case .general:   "gear"
        case .shortcuts: "command.square"
        case .voice:     "mic.fill"
        case .trading:   "chart.line.uptrend.xyaxis"
        case .system:    "checkmark.shield"
        }
    }
}

// MARK: - Settings Window Container

struct SettingsView: View {
    @State private var selectedPane: SettingsPane? = .general
    @State private var searchText = ""

    private var filteredPanes: [SettingsPane] {
        if searchText.isEmpty { return SettingsPane.allCases }
        return SettingsPane.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Sidebar
            sidebar
                .frame(width: 220)
                .background(Color(NSColor.controlBackgroundColor))

            // MARK: Divider
            Divider()
                .opacity(0.4)

            // MARK: Detail
            detailView(for: selectedPane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 550, idealHeight: 650)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.textBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Pane list
            List(selection: $selectedPane) {
                Section {
                    ForEach(filteredPanes) { pane in
                        SidebarRow(
                            pane: pane,
                            isSelected: selectedPane == pane
                        )
                        .tag(pane)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)
        }
    }

    // MARK: Detail View Router

    @ViewBuilder
    private func detailView(for pane: SettingsPane?) -> some View {
        switch pane {
        case .general:   GeneralPane()
        case .shortcuts: ShortcutsPane()
        case .voice:     VoicePane()
        case .trading:   TradingPane()
        case .system:    SystemPane()
        case .none:      EmptyView()
        }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pane.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 18, alignment: .center)

            Text(pane.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Detail Container with Toolbar

struct DetailContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()
                .opacity(0.4)

            // Scrollable content
            ScrollView {
                VStack(spacing: 20) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }
}

// MARK: - Modern Section Card

struct SettingsCard<Content: View>: View {
    let header: String?
    let footer: String?
    @ViewBuilder let content: Content

    init(header: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = header {
                Text(header)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.25), lineWidth: 0.5)
            )

            if let footer = footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Modern Row

struct SettingsRow<Content: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Content
    let showDivider: Bool

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        showDivider: Bool = true,
        @ViewBuilder trailing: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.showDivider = showDivider
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, alignment: .center)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                trailing
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if showDivider {
                Divider()
                    .padding(.leading, icon != nil ? 42 : 12)
                    .opacity(0.3)
            }
        }
    }
}

// MARK: - General Pane

struct GeneralPane: View {
    @AppStorage("selectedProvider") private var selectedProviderRaw = LLMProvider.openRouter.rawValue
    @AppStorage("customHost")       private var customHost          = ""
    @AppStorage("apiBaseURL")       private var apiBaseURL    = "https://openrouter.ai/api/v1"
    @AppStorage("apiKey")           private var apiKey        = ""
    @AppStorage("modelName")        private var modelName     = "openai/gpt-4o-mini"
    @AppStorage("systemPrompt")     private var systemPrompt  = SettingsManager.defaultSystemPrompt
    @AppStorage("showFloatingIndicator") private var showFloatingIndicator = true

    @State private var showAPIKey = false

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: selectedProviderRaw) ?? .openRouter
    }

    var body: some View {
        DetailContainer(title: "General") {
            // Provider
            SettingsCard(header: "AI Provider") {
                VStack(alignment: .leading, spacing: 12) {
                    providerGrid
                        .padding(12)
                }
            }

            // Connection
            SettingsCard(header: "Connection") {
                if selectedProvider.showsBaseURLField {
                    SettingsRow(icon: "link", title: "Base URL", showDivider: true) {
                        TextField("", text: $apiBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }

                if selectedProvider.isLocal {
                    SettingsRow(icon: "externaldrive.connected.to.line.below", title: "Host", subtitle: "The path \"/v1\" will be appended automatically", showDivider: true) {
                        TextField("", text: $customHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: customHost) { _, host in
                                updateBaseURLFromHost(host)
                            }
                    }
                }

                if selectedProvider.requiresAPIKey {
                    SettingsRow(icon: "key", title: "API Key", showDivider: true) {
                        HStack(spacing: 6) {
                            if showAPIKey {
                                TextField(selectedProvider.apiKeyPlaceholder, text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField(selectedProvider.apiKeyPlaceholder, text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 220)
                    }
                }

                SettingsRow(icon: "cpu", title: "Model", showDivider: false) {
                    TextField(selectedProvider.defaultModel, text: $modelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }

            // Indicator
            SettingsCard(header: "Appearance", footer: "A small pulsing dot appears at the bottom-right corner of your screen while fixing text.") {
                SettingsRow(icon: "circle.fill", title: "Floating Indicator", showDivider: false) {
                    Toggle("", isOn: $showFloatingIndicator)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            // System Prompt
            SettingsCard(header: "System Prompt") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)

                    HStack {
                        Spacer()
                        Button("Reset to Default") {
                            systemPrompt = SettingsManager.defaultSystemPrompt
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    }
                }
                .padding(12)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedProviderRaw)
    }

    private var providerGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(LLMProvider.allCases) { provider in
                ProviderPill(
                    provider: provider,
                    isSelected: selectedProvider == provider
                ) {
                    selectProvider(provider)
                }
            }
        }
    }

    private func selectProvider(_ provider: LLMProvider) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedProviderRaw = provider.rawValue
        }
        if let fixed = provider.fixedBaseURL {
            apiBaseURL = fixed
        } else {
            let host = customHost.isEmpty ? provider.defaultHost : customHost
            updateBaseURLFromHost(host)
        }
        modelName = provider.defaultModel
        showAPIKey = false
    }

    private func updateBaseURLFromHost(_ host: String) {
        let trimmed = host.hasSuffix("/") ? String(host.dropLast()) : host
        if trimmed.isEmpty {
            apiBaseURL = selectedProvider.defaultHost + "/v1"
        } else {
            apiBaseURL = trimmed + "/v1"
        }
    }
}

// MARK: - Shortcuts Pane

struct ShortcutsPane: View {
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode = 3
    @AppStorage("hotkeyCommand") private var hotkeyCommand = true
    @AppStorage("hotkeyShift")   private var hotkeyShift   = true
    @AppStorage("hotkeyOption")  private var hotkeyOption  = false
    @AppStorage("hotkeyControl") private var hotkeyControl = false

    @AppStorage("voiceHotkeyKeyCode")  private var voiceHotkeyKeyCode  = 9
    @AppStorage("voiceHotkeyCommand")  private var voiceHotkeyCommand  = false
    @AppStorage("voiceHotkeyShift")    private var voiceHotkeyShift    = false
    @AppStorage("voiceHotkeyOption")   private var voiceHotkeyOption   = true
    @AppStorage("voiceHotkeyControl")  private var voiceHotkeyControl  = true

    @State private var isRecordingHotkey      = false
    @State private var isRecordingVoiceHotkey = false

    var body: some View {
        DetailContainer(title: "Shortcuts") {
            SettingsCard(header: "Grammar Fix", footer: "Press this shortcut to fix the selected text.") {
                SettingsRow(icon: "sparkles", title: "Trigger", showDivider: false) {
                    HotkeyRecorderButton(
                        isRecording: $isRecordingHotkey,
                        displayString: SettingsManager.shared.displayString
                    ) { keyCode, modifiers in
                        hotkeyKeyCode = keyCode
                        hotkeyCommand = modifiers.contains(.command)
                        hotkeyShift   = modifiers.contains(.shift)
                        hotkeyOption  = modifiers.contains(.option)
                        hotkeyControl = modifiers.contains(.control)
                        HotkeyManager.shared.reinstall()
                    }
                }
            }

            SettingsCard(header: "Voice Dictation", footer: "Press this shortcut to start/stop voice recording.") {
                SettingsRow(icon: "mic.fill", title: "Trigger", showDivider: false) {
                    HotkeyRecorderButton(
                        isRecording: $isRecordingVoiceHotkey,
                        displayString: SettingsManager.shared.voiceDisplayString
                    ) { keyCode, modifiers in
                        voiceHotkeyKeyCode  = keyCode
                        voiceHotkeyCommand  = modifiers.contains(.command)
                        voiceHotkeyShift    = modifiers.contains(.shift)
                        voiceHotkeyOption   = modifiers.contains(.option)
                        voiceHotkeyControl  = modifiers.contains(.control)
                        HotkeyManager.shared.reinstall()
                    }
                }
            }
        }
    }
}

// MARK: - Voice Pane

struct VoicePane: View {
    @AppStorage("voiceDictationEnabled") private var voiceDictationEnabled = true
    private let stt = SpeechToTextService.shared

    var body: some View {
        DetailContainer(title: "Voice") {
            SettingsCard(header: "Voice Dictation") {
                SettingsRow(icon: "mic.fill", title: "Enable Voice Dictation", showDivider: false) {
                    Toggle("", isOn: $voiceDictationEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: voiceDictationEnabled) { _, _ in
                            HotkeyManager.shared.reinstall()
                        }
                }
            }

            if voiceDictationEnabled {
                modelStatusCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: voiceDictationEnabled)
        .onAppear {
            stt.checkReadiness()
        }
    }

    @ViewBuilder
    private var modelStatusCard: some View {
        switch stt.setupState {
        case .unknown, .notSetup:
            SettingsCard(header: "Model Status", footer: "~600 MB download via uv. Stored in HuggingFace cache.") {
                SettingsRow(icon: "arrow.down.circle", title: "Parakeet model not installed", subtitle: "Local transcription requires the Parakeet model.", showDivider: false) {
                    Button("Set Up") {
                        Task { await stt.setupAndDownload() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

        case .settingUp:
            SettingsCard(header: "Model Status") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Installing parakeet-mlx…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !stt.setupLog.isEmpty {
                        SetupLogView(lines: stt.setupLog)
                    }
                }
                .padding(12)
            }

        case .downloadingModel:
            SettingsCard(header: "Model Status") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text(stt.setupProgress.isEmpty ? "Downloading model…" : stt.setupProgress)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !stt.setupLog.isEmpty {
                        SetupLogView(lines: stt.setupLog)
                    }
                }
                .padding(12)
            }

        case .ready:
            SettingsCard(header: "Model Status") {
                SettingsRow(icon: "checkmark.circle.fill", title: "Parakeet model ready", showDivider: false) {
                    EmptyView()
                }
            }

        case let .error(msg):
            SettingsCard(header: "Model Status") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Setup failed")
                                .font(.subheadline)
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Retry") {
                            Task { await stt.setupAndDownload() }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Trading Pane

struct TradingPane: View {
    @AppStorage("kiteApiKey")       private var kiteApiKey       = ""
    @AppStorage("kiteApiSecret")    private var kiteApiSecret    = ""
    @AppStorage("kiteAccessToken")  private var kiteAccessToken  = ""

    private var isConnected: Bool { !kiteAccessToken.isEmpty }

    var body: some View {
        DetailContainer(title: "Trading") {
            // Status
            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: isConnected ? "checkmark.circle.fill" : "building.columns.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(isConnected ? .green : Color.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isConnected ? "Connected" : "Kite (Zerodha)")
                            .font(.system(size: 15, weight: .semibold))
                        Text(isConnected ? "Your Kite account is linked." : "Connect your Zerodha account to view portfolio.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isConnected {
                        Button("Logout") {
                            KiteAuthManager.shared.logout()
                            kiteAccessToken = ""
                            kiteApiKey = ""
                            kiteApiSecret = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                }
                .padding(16)
            }

            if let msg = KiteAuthManager.shared.authError {
                SettingsCard {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(12)
                }
            }

            // Credentials
            SettingsCard(header: "Credentials") {
                SettingsRow(icon: "key", title: "API Key", showDivider: true) {
                    HStack(spacing: 6) {
                        SecureField("kite_api_key_…", text: $kiteApiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Button {
                            kiteApiKey = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .opacity(kiteApiKey.isEmpty ? 0 : 1)
                    }
                }

                SettingsRow(icon: "lock.shield", title: "API Secret", showDivider: true) {
                    HStack(spacing: 6) {
                        SecureField("kite_api_secret_…", text: $kiteApiSecret)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Button {
                            kiteApiSecret = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .opacity(kiteApiSecret.isEmpty ? 0 : 1)
                    }
                }

                SettingsRow(icon: "link", title: "Callback URL", subtitle: "Set this redirect URL in your Kite Connect app.", showDivider: false) {
                    Text(KiteHTTPServer.shared.callbackURL)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // Login
            if !isConnected {
                SettingsCard {
                    HStack {
                        Spacer()
                        Button {
                            KiteAuthManager.shared.beginLogin()
                        } label: {
                            if KiteAuthManager.shared.isLoggingIn {
                                HStack(spacing: 4) {
                                    ProgressView().scaleEffect(0.6)
                                    Text("Logging in…")
                                }
                            } else {
                                Text("Login to Kite")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(
                            kiteApiKey.trimmingCharacters(in: .whitespaces).isEmpty ||
                            kiteApiSecret.trimmingCharacters(in: .whitespaces).isEmpty ||
                            KiteAuthManager.shared.isLoggingIn
                        )
                        Spacer()
                    }
                    .padding(16)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: kiteAccessToken)
        .animation(.easeInOut(duration: 0.2), value: KiteAuthManager.shared.isLoggingIn)
    }
}

// MARK: - System Pane

struct SystemPane: View {
    @State private var accessibilityGranted = false
    @State private var startAtLogin         = (SMAppService.mainApp.status == .enabled)
    @State private var loginItemError: String? = nil

    var body: some View {
        DetailContainer(title: "System") {
            SettingsCard(header: "Launch") {
                SettingsRow(icon: "power", title: "Start at Login", showDivider: false) {
                    Toggle("", isOn: $startAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: startAtLogin) { _, enabled in
                            applyLoginItem(enabled)
                        }
                }

                if let err = loginItemError {
                    HStack {
                        Spacer()
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }

            SettingsCard(header: "Permissions", footer: "Required to detect keyboard shortcuts and paste fixed text.") {
                SettingsRow(
                    icon: accessibilityGranted ? "checkmark.shield.fill" : "xmark.shield.fill",
                    title: "Accessibility Access",
                    subtitle: accessibilityGranted ? "Poop can control your Mac." : "Poop needs permission to automate your Mac.",
                    showDivider: false
                ) {
                    if !accessibilityGranted {
                        Button("Open System Settings") {
                            AccessibilityManager.shared.requestPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: loginItemError)
        .onAppear {
            refreshAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibility()
        }
    }

    private func applyLoginItem(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            startAtLogin = !enable
            loginItemError = "Could not \(enable ? "enable" : "disable") start at login: \(error.localizedDescription)"
        }
    }

    private func refreshAccessibility() {
        accessibilityGranted = AccessibilityManager.shared.checkPermission()
    }
}

// MARK: - Provider Pill

struct ProviderPill: View {
    let provider: LLMProvider
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: provider.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 14)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.accentColor
                          : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.clear : Color(NSColor.separatorColor),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hotkey Recorder Button

struct HotkeyRecorderButton: View {
    @Binding var isRecording: Bool
    let displayString: String
    let onRecorded: (_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags) -> Void

    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Press shortcut…" : displayString)
                .monospacedDigit()
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 100, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isRecording
                            ? Color.accentColor.opacity(0.15)
                            : Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color(NSColor.separatorColor),
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !mods.isEmpty else { return event }

            onRecorded(Int(event.keyCode), mods)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - Setup Log View

struct SetupLogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .id(idx)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 120)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .onChange(of: lines.count) { _, _ in
                if let last = lines.indices.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }
}
