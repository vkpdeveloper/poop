
import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    // Provider + derived URL storage
    @AppStorage("selectedProvider") private var selectedProviderRaw = LLMProvider.openRouter.rawValue
    @AppStorage("customHost")       private var customHost          = ""

    // API fields
    @AppStorage("apiBaseURL")    private var apiBaseURL    = "https://openrouter.ai/api/v1"
    @AppStorage("apiKey")        private var apiKey        = ""
    @AppStorage("modelName")     private var modelName     = "openai/gpt-4o-mini"
    @AppStorage("systemPrompt")  private var systemPrompt  = SettingsManager.defaultSystemPrompt

    // Hotkey fields
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode = 3
    @AppStorage("hotkeyCommand") private var hotkeyCommand = true
    @AppStorage("hotkeyShift")   private var hotkeyShift   = true
    @AppStorage("hotkeyOption")  private var hotkeyOption  = false
    @AppStorage("hotkeyControl") private var hotkeyControl = false
    @AppStorage("showFloatingIndicator") private var showFloatingIndicator = true

    @State private var isRecordingHotkey   = false
    @State private var accessibilityGranted = false
    @State private var showAPIKey           = false
    @State private var startAtLogin         = (SMAppService.mainApp.status == .enabled)
    @State private var loginItemError: String? = nil

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: selectedProviderRaw) ?? .openRouter
    }

    // MARK: - Body

    var body: some View {
        Form {
            apiSection
            shortcutSection
            indicatorSection
            launchSection
            systemPromptSection
            permissionsSection
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 800)
        .onAppear { refreshAccessibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibility()
        }
    }

    // MARK: - API Section

    private var apiSection: some View {
        Section {
            // Provider picker
            VStack(alignment: .leading, spacing: 10) {
                Label("Provider", systemImage: "network")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                providerGrid
            }
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 2)

            // Base URL — only for OpenAI and Anthropic (editable)
            if selectedProvider.showsBaseURLField {
                LabeledContent {
                    TextField(selectedProvider.fixedBaseURL ?? "", text: $apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                } label: {
                    fieldLabel("Base URL", icon: "link")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Host — only for local providers (Ollama, LM Studio)
            if selectedProvider.isLocal {
                LabeledContent {
                    TextField(selectedProvider.defaultHost, text: $customHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                        .onChange(of: customHost) { _, host in
                            updateBaseURLFromHost(host)
                        }
                } label: {
                    fieldLabel("Host", icon: "externaldrive.connected.to.line.below")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                Text("The path \"/v1\" will be appended automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // API Key — hidden for local providers
            if selectedProvider.requiresAPIKey {
                LabeledContent {
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
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(showAPIKey ? "Hide API key" : "Show API key")
                    }
                    .frame(maxWidth: 300)
                } label: {
                    fieldLabel("API Key", icon: "key")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Model
            LabeledContent {
                TextField(selectedProvider.defaultModel, text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            } label: {
                fieldLabel("Model", icon: "cpu")
            }
        } header: {
            Text("API Configuration")
        }
        .animation(.easeInOut(duration: 0.2), value: selectedProviderRaw)
    }

    // MARK: - Provider Grid

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

    // MARK: - Indicator Section

    private var indicatorSection: some View {
        Section {
            Toggle(isOn: $showFloatingIndicator) {
                Label("Floating Indicator", systemImage: "circle.fill")
            }

            if showFloatingIndicator {
                Text("A small pulsing dot appears at the bottom-right corner of your screen while fixing text — useful when the menu bar is hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Text("Indicator")
        }
        .animation(.easeInOut(duration: 0.2), value: showFloatingIndicator)
    }

    // MARK: - Shortcut Section

    private var shortcutSection: some View {
        Section("Keyboard Shortcut") {
            LabeledContent {
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
            } label: {
                fieldLabel("Trigger", icon: "command.square")
            }
        }
    }

    // MARK: - Launch Section

    private var launchSection: some View {
        Section {
            Toggle(isOn: $startAtLogin) {
                Label("Start at Login", systemImage: "power")
            }
            .onChange(of: startAtLogin) { _, enabled in
                applyLoginItem(enabled)
            }

            if let err = loginItemError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        } header: {
            Text("Launch")
        }
        .animation(.easeInOut(duration: 0.2), value: loginItemError)
    }

    // MARK: - System Prompt Section

    private var systemPromptSection: some View {
        Section("System Prompt") {
            TextEditor(text: $systemPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)

            Button("Reset to Default") {
                systemPrompt = SettingsManager.defaultSystemPrompt
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        Section("Permissions") {
            HStack(spacing: 8) {
                Image(systemName: accessibilityGranted
                      ? "checkmark.circle.fill"
                      : "xmark.circle.fill")
                    .foregroundStyle(accessibilityGranted ? .green : .red)

                Text("Accessibility Access")

                Spacer()

                if !accessibilityGranted {
                    Button("Open System Settings") {
                        AccessibilityManager.shared.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if !accessibilityGranted {
                Text("Required to detect your keyboard shortcut and paste the fixed text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func applyLoginItem(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            // Roll the toggle back on failure
            startAtLogin = !enable
            loginItemError = "Could not \(enable ? "enable" : "disable") start at login: \(error.localizedDescription)"
        }
    }

    private func fieldLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .foregroundStyle(.primary)
    }

    private func selectProvider(_ provider: LLMProvider) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedProviderRaw = provider.rawValue
        }
        // Set base URL from the provider's known URL or from the stored/default host
        if let fixed = provider.fixedBaseURL {
            apiBaseURL = fixed
        } else {
            let host = customHost.isEmpty ? provider.defaultHost : customHost
            updateBaseURLFromHost(host)
        }
        // Suggest the provider's default model
        modelName = provider.defaultModel
        // Reset show-key state when switching
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
