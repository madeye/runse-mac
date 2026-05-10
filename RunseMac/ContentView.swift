import RunseCore
import SwiftData
import SwiftUI

// MARK: - Sidebar

private enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case providers, settings, history
    var id: String { rawValue }

    var title: String {
        switch self {
        case .providers: "Providers"
        case .settings: "Settings"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .providers: "server.rack"
        case .settings: "gearshape"
        case .history: "clock"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .providers

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("Runse")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            switch selection ?? .providers {
            case .providers: ProvidersView()
            case .settings:  SettingsView()
            case .history:   HistoryView()
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Runse")
                .font(.caption.weight(.semibold))
            Text("Version \(AppInfo.versionDisplay)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Providers

struct ProvidersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProviderProfile.name) private var profiles: [ProviderProfile]

    @State private var selectedProfileID: String?

    /// The seeded built-in default provider is intentionally hidden from the UI;
    /// it powers the fallback transform path but should not be user-visible or
    /// user-editable.
    private var visibleProfiles: [ProviderProfile] {
        profiles.filter { !$0.isDefault }
    }

    private var selectedProfile: ProviderProfile? {
        visibleProfiles.first { $0.id == selectedProfileID } ?? visibleProfiles.first
    }

    var body: some View {
        Group {
            if visibleProfiles.isEmpty {
                ContentUnavailableView {
                    Label("No Providers", systemImage: "server.rack")
                } description: {
                    Text("Add an OpenAI- or Anthropic-compatible provider to get started.")
                } actions: {
                    Menu {
                        ForEach(ProviderPreset.allCases) { preset in
                            Button(preset.title) { addProvider(preset: preset) }
                        }
                    } label: {
                        Label("Add Provider", systemImage: "plus")
                    }
                    .menuStyle(.borderedButton)
                }
            } else {
                HSplitView {
                    providerList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                    if let selectedProfile {
                        ProviderEditorView(profile: selectedProfile)
                            .id(selectedProfile.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("Select a provider", systemImage: "server.rack")
                    }
                }
            }
        }
        .navigationTitle("Providers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ProviderPreset.allCases) { preset in
                        Button(preset.title) { addProvider(preset: preset) }
                    }
                } label: {
                    Label("Add Provider", systemImage: "plus")
                }
                .menuIndicator(.visible)
                .help("Add a provider from a preset, or pick Custom to fill everything in manually")
            }
        }
        .task {
            if profiles.isEmpty {
                try? Bootstrap.seedDefaultsIfNeeded(context: modelContext)
            }
            selectedProfileID = selectedProfileID ?? visibleProfiles.first?.id
        }
    }

    private var providerList: some View {
        List(selection: $selectedProfileID) {
            ForEach(visibleProfiles) { profile in
                ProviderRow(profile: profile)
                    .tag(profile.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            modelContext.delete(profile)
                            try? modelContext.save()
                            if selectedProfileID == profile.id {
                                selectedProfileID = visibleProfiles.first { $0.id != profile.id }?.id
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func addProvider(preset: ProviderPreset = .custom) {
        let profile: ProviderProfile
        if let configuration = preset.configuration {
            profile = ProviderProfile(
                name: configuration.name,
                kind: configuration.kind,
                baseURL: configuration.baseURL,
                chatEndpoint: configuration.endpoint,
                model: configuration.model,
                extraHeadersJSON: configuration.extraHeaders
            )
        } else {
            profile = ProviderProfile(
                name: "Custom Provider",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com",
                chatEndpoint: "/v1/chat/completions",
                model: "gpt-4.1-mini"
            )
        }
        modelContext.insert(profile)
        try? modelContext.save()
        selectedProfileID = profile.id
    }
}

private struct ProviderRow: View {
    @Bindable var profile: ProviderProfile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body)
                    .lineLimit(1)
                Text(profile.model.isEmpty ? profile.kind.title : profile.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            statusBadge
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch profile.apiTestStatus {
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .testing:
            ProgressView().controlSize(.small)
        case .untested:
            EmptyView()
        }
    }
}

// MARK: - Provider Editor

struct ProviderEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: ProviderProfile

    @State private var apiKey = ""
    @State private var statusMessage: String?
    @State private var isTesting = false
    @State private var isSavingKey = false
    @State private var preset: ProviderPreset = .custom

    var body: some View {
        Form {
            Section("Preset") {
                Picker("Provider", selection: $preset) {
                    ForEach(ProviderPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .onChange(of: preset) { _, value in
                    applyPreset(value)
                }
            }

            Section("Endpoint") {
                TextField("Name", text: $profile.name)
                Picker("Type", selection: $profile.kind) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .disabled(preset != .custom)
                TextField("Base URL", text: $profile.baseURL)
                    .textContentType(.URL)
                    .disabled(preset != .custom)
                TextField("Path", text: $profile.chatEndpoint)
                    .disabled(preset != .custom)
                TextField("Model", text: $profile.model)
                    .disabled(preset != .custom)
            }

            Section("Headers") {
                TextField("Extra headers (JSON)", text: $profile.extraHeadersJSON, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Authentication") {
                SecureField("API Key", text: $apiKey)
                HStack {
                    Spacer()
                    Button {
                        Task { await saveAPIKey() }
                    } label: {
                        if isSavingKey {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save Key")
                        }
                    }
                    .disabled(isSavingKey)
                }
            }

            Section("Connection") {
                HStack(spacing: 10) {
                    Group {
                        switch profile.apiTestStatus {
                        case .passed:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        case .testing:
                            ProgressView().controlSize(.small)
                        case .untested:
                            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionTitle).font(.callout)
                        if let detail = connectionDetail {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await testProvider() }
                    } label: {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Test", systemImage: "checkmark.circle")
                        }
                    }
                    .disabled(isTesting)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: profile.name) { _, _ in save() }
        .onChange(of: profile.kindRawValue) { _, _ in save() }
        .onChange(of: profile.baseURL) { _, _ in save() }
        .onChange(of: profile.chatEndpoint) { _, _ in save() }
        .onChange(of: profile.model) { _, _ in save() }
        .onChange(of: profile.extraHeadersJSON) { _, _ in save() }
        .task {
            preset = ProviderPreset.infer(from: profile)
            await loadAPIKey()
        }
    }

    private func applyPreset(_ preset: ProviderPreset) {
        guard let configuration = preset.configuration else { return }
        let nameIsAutoManaged = profile.name.isEmpty || ProviderPreset.allPresetNames.contains(profile.name)
        if nameIsAutoManaged {
            profile.name = configuration.name
        }
        profile.kind = configuration.kind
        profile.baseURL = configuration.baseURL
        profile.chatEndpoint = configuration.endpoint
        profile.model = configuration.model
        profile.extraHeadersJSON = configuration.extraHeaders
        save()
    }

    private var connectionTitle: String {
        switch profile.apiTestStatus {
        case .passed: "Connection passed"
        case .failed: "Connection failed"
        case .testing: "Testing…"
        case .untested: "Not yet tested"
        }
    }

    private var connectionDetail: String? {
        if let message = profile.apiTestMessage, !message.isEmpty { return message }
        if let date = profile.apiTestedAt {
            let formatter = RelativeDateTimeFormatter()
            return "Last run \(formatter.localizedString(for: date, relativeTo: .now))"
        }
        return nil
    }

    private func save() {
        profile.updatedAt = .now
        try? modelContext.save()
    }

    private func loadAPIKey() async {
        let keychain = KeychainStore(accessGroup: KeychainAccessGroup.current())
        apiKey = (try? await keychain.load(service: SecretSeeder.service, account: profile.id)) ?? ""
    }

    private func saveAPIKey() async {
        isSavingKey = true
        defer { isSavingKey = false }
        save()
        do {
            let keychain = KeychainStore(accessGroup: KeychainAccessGroup.current())
            try await keychain.save(apiKey, service: SecretSeeder.service, account: profile.id)
            statusMessage = "API key saved."
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func testProvider() async {
        isTesting = true
        defer { isTesting = false }
        await saveAPIKey()
        do {
            let result = try await ProviderAPITester.test(profile: profile, apiKey: apiKey)
            profile.apiTestStatus = .passed
            profile.apiTestMessage = result.message
            profile.apiTestedAt = .now
            save()
            statusMessage = nil
        } catch {
            profile.apiTestStatus = .failed
            profile.apiTestMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            profile.apiTestedAt = .now
            save()
            statusMessage = nil
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @State private var defaultLanguage = SettingsStore().defaultTranslationLanguage
    @State private var popoverEnabled = SettingsStore().selectionPopoverEnabled
    @State private var accessibilityTrusted = AccessibilityReader.ensureTrusted(prompt: false)
    private let settings = SettingsStore()

    var body: some View {
        Form {
            Section("General") {
                TextField("Default translation language", text: $defaultLanguage)
                    .onChange(of: defaultLanguage) { _, value in
                        settings.defaultTranslationLanguage = value
                    }
            }

            Section("Quick Actions") {
                LabeledContent("Hotkeys") {
                    HStack(spacing: 12) {
                        ShortcutChip(label: "Refine", keys: "⌃⌥R")
                        ShortcutChip(label: "Translate", keys: "⌃⌥T")
                    }
                }
                Toggle("Show floating action bar near selected text", isOn: $popoverEnabled)
                    .onChange(of: popoverEnabled) { _, value in
                        settings.selectionPopoverEnabled = value
                        NotificationCenter.default.post(name: .runseSelectionPopoverEnabledChanged, object: value)
                    }
                accessibilityRow
            }

            Section {
                Text("Runse also appears under the Services submenu in compatible text-selection context menus as **Refine Text** and **Translate Text**.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Refresh Services Registry") {
                    NSUpdateDynamicServices()
                }
            } header: {
                Text("Services")
            }

            Section("About") {
                LabeledContent("Version", value: AppInfo.versionDisplay)
                LabeledContent("Bundle", value: AppInfo.bundleIdentifier)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .onAppear { accessibilityTrusted = AccessibilityReader.ensureTrusted(prompt: false) }
    }

    @ViewBuilder
    private var accessibilityRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(accessibilityTrusted ? .green : .orange)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(accessibilityTrusted ? "Accessibility access granted" : "Accessibility access required")
                    .font(.callout.weight(.medium))
                Text(accessibilityTrusted
                     ? "Hotkeys and the floating action bar can read selected text in any app."
                     : "Without it, hotkeys still register but cannot read selected text from other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !accessibilityTrusted {
                Button("Open Settings") {
                    AccessibilityReader.ensureTrusted(prompt: true)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

private struct ShortcutChip: View {
    let label: String
    let keys: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(keys)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

extension Notification.Name {
    static let runseSelectionPopoverEnabledChanged = Notification.Name("runse.selectionPopover.enabledChanged")
}

// MARK: - History

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransformHistory.timestamp, order: .reverse) private var history: [TransformHistory]

    var body: some View {
        Group {
            if history.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock",
                    description: Text("Refined and translated transforms will appear here.")
                )
            } else {
                List {
                    ForEach(history) { item in
                        HistoryRow(item: item)
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(history[index]) }
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !history.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        for item in history { modelContext.delete(item) }
                        try? modelContext.save()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let item: TransformHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.actionRawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(actionColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(actionColor)
                Text(item.providerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(item.sourceExcerpt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(item.resultExcerpt)
                .font(.callout)
                .lineLimit(2)
            Text(item.model)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var actionColor: Color {
        item.actionRawValue == TransformAction.translate.rawValue ? .blue : .purple
    }
}

// MARK: - App info

enum AppInfo {
    static var versionDisplay: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "—"
    }
}
