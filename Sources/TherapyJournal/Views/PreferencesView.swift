import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @State private var config = AppConfig.load()
    @State private var claudeSessionKey: String = ""
    @State private var claudeAPIKey: String = ""
    @State private var sendTimeHour: Int = 20
    @State private var sendTimeMinute: Int = 0
    @State private var showSaveConfirmation = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            credentialsTab
                .tabItem { Label("Credentials", systemImage: "key") }
        }
        .frame(width: 520, height: 460)
        .onAppear(perform: loadCredentials)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Email Addresses") {
                TextField("Your email", text: $config.userEmail)
                    .textFieldStyle(.roundedBorder)
                TextField("Therapist's email", text: $config.therapistEmail)
                    .textFieldStyle(.roundedBorder)
                Text("Emails are sent via your local Mail.app account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Calendar") {
                TextField("Session keyword (e.g. \"Therapy\", \"Dr. Smith\")", text: $config.calendarKeyword)
                    .textFieldStyle(.roundedBorder)
                Text("Searches all calendars in your macOS Calendar app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Summary Schedule") {
                HStack {
                    Text("Send summary at:")
                    Picker("Hour", selection: $sendTimeHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .frame(width: 70)
                    Text(":")
                    Picker("Minute", selection: $sendTimeMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .frame(width: 70)
                }
            }

            Section("Claude Journal Project") {
                TextField("Project URL (claude.ai)", text: $config.claudeProjectURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Organization ID", text: $config.claudeProjectOrgID)
                    .textFieldStyle(.roundedBorder)
                TextField("Project ID", text: $config.claudeProjectID)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                Toggle("Launch at Login", isOn: $config.launchAtLogin)
            }

            HStack {
                Spacer()
                if showSaveConfirmation {
                    Text("Saved!")
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                Button("Save") {
                    saveGeneral()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Credentials Tab

    private var credentialsTab: some View {
        Form {
            Section("Claude Session Key") {
                Text("Paste your sessionKey from browser DevTools (Application > Cookies > claude.ai)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("Session Key", text: $claudeSessionKey)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Claude API Key") {
                Text("Your Anthropic API key for summary generation")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("API Key (sk-ant-...)", text: $claudeAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                if showSaveConfirmation {
                    Text("Saved!")
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                Button("Save Credentials") {
                    saveCredentials()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func loadCredentials() {
        sendTimeHour = config.summarySendTime.hour ?? 20
        sendTimeMinute = config.summarySendTime.minute ?? 0

        if let key = try? KeychainManager.shared.retrieve(key: .claudeSessionKey) {
            claudeSessionKey = key
        }
        if let key = try? KeychainManager.shared.retrieve(key: .claudeAPIKey) {
            claudeAPIKey = key
        }
    }

    private func saveGeneral() {
        config.summarySendTime = DateComponents(hour: sendTimeHour, minute: sendTimeMinute)
        do {
            try config.save()
            updateLaunchAtLogin()
            flashSaved()
            AppLogger.shared.info("General preferences saved")
        } catch {
            AppLogger.shared.error("Failed to save preferences: \(error)")
        }
    }

    private func saveCredentials() {
        do {
            if !claudeSessionKey.isEmpty {
                try KeychainManager.shared.save(key: .claudeSessionKey, value: claudeSessionKey)
            }
            if !claudeAPIKey.isEmpty {
                try KeychainManager.shared.save(key: .claudeAPIKey, value: claudeAPIKey)
            }
            flashSaved()
            AppLogger.shared.info("Credentials saved to Keychain")
        } catch {
            AppLogger.shared.error("Failed to save credentials: \(error)")
        }
    }

    private func updateLaunchAtLogin() {
        do {
            if config.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLogger.shared.error("Failed to update launch at login: \(error)")
        }
    }

    private func flashSaved() {
        withAnimation {
            showSaveConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSaveConfirmation = false
            }
        }
    }
}
