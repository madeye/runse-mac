import AppKit
import RunseCore
import SwiftData
import SwiftUI

struct TransformWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissWindow) private var dismissWindow
    @Query(sort: \ProviderProfile.name) private var profiles: [ProviderProfile]
    @Query(sort: \PromptTemplate.name) private var templates: [PromptTemplate]

    let selectedText: String
    let initialAction: TransformAction
    let close: (NSWindow?) -> Void

    @State private var action: TransformAction
    @State private var tone: Tone = .natural
    @State private var formality: Formality = .neutral
    @State private var length: OutputLength = .same
    @State private var targetLanguage = SettingsStore().defaultTranslationLanguage
    @State private var customInstruction = ""
    @State private var result = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var didCopy = false
    @State private var completedRequestFingerprint: String?

    init(selectedText: String, initialAction: TransformAction, close: @escaping (NSWindow?) -> Void) {
        self.selectedText = selectedText
        self.initialAction = initialAction
        self.close = close
        _action = State(initialValue: initialAction)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Action", selection: $action) {
                        ForEach(TransformAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                switch action {
                case .refine:
                    Section("Refine Options") {
                        Picker("Tone", selection: $tone) {
                            ForEach(Tone.allCases) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        Picker("Formality", selection: $formality) {
                            ForEach(Formality.allCases) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        Picker("Length", selection: $length) {
                            ForEach(OutputLength.allCases) { Text($0.rawValue.capitalized).tag($0) }
                        }
                    }
                case .translate:
                    Section("Translate Options") {
                        Picker("Common languages", selection: $targetLanguage) {
                            ForEach(CommonTargetLanguage.all) { language in
                                Text(language.title).tag(language.value)
                            }
                        }
                        TextField("Target language", text: $targetLanguage)
                    }
                case .pinyin:
                    EmptyView()
                }

                Section("Custom Instruction") {
                    TextField("Optional, e.g. \"keep it under 30 words\"", text: $customInstruction, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Selected Text") {
                    ScrollView {
                        Text(selectedText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }

                Section("Result") {
                    if isLoading && result.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Running…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            TextEditor(text: $result)
                                .font(.body)
                                .frame(minHeight: 180)
                                .scrollContentBackground(.hidden)
                            if isLoading {
                                ProgressView().controlSize(.small).padding(.top, 4)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("transform.form")

            Divider()

            HStack(spacing: 8) {
                providerSummary
                Spacer()
                Button("Close") { close(NSApp.keyWindow) }
                    .keyboardShortcut(.cancelAction)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(result.isEmpty || isLoading)
                Button {
                    Task { await runTransform() }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Run", systemImage: "wand.and.stars")
                    }
                }
                .accessibilityIdentifier("transform.run")
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(selectedText.isEmpty || isLoading)
            }
            .padding(12)
            .background(.bar)
        }
        .task {
            if profiles.isEmpty || templates.isEmpty {
                try? Bootstrap.seedDefaultsIfNeeded(context: modelContext)
            }
        }
        .accessibilityIdentifier("transform.window")
    }

    @ViewBuilder
    private var providerSummary: some View {
        let profile = profiles.first(where: \.isDefault) ?? profiles.first
        if let profile {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                Text(profile.name)
                    .lineLimit(1)
                if !profile.model.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(profile.model)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func runTransform() async {
        let requestFingerprint = transformRequestFingerprint
        guard result.isEmpty || completedRequestFingerprint != requestFingerprint else {
            return
        }

        isLoading = true
        errorMessage = nil
        didCopy = false
        defer { isLoading = false }

        do {
            result = ""
            let runner = TransformRunner(modelContext: modelContext, profiles: profiles, templates: templates)
            result = try await runner.run(
                selectedText: selectedText,
                action: action,
                targetLanguage: targetLanguage,
                tone: tone,
                length: length,
                formality: formality,
                customInstruction: customInstruction
            ) { partial in
                result = partial
            }
            completedRequestFingerprint = requestFingerprint
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var transformRequestFingerprint: String {
        [
            selectedText,
            action.rawValue,
            targetLanguage,
            tone.rawValue,
            length.rawValue,
            formality.rawValue,
            customInstruction
        ].joined(separator: "\u{1F}")
    }
}

private struct CommonTargetLanguage: Identifiable {
    let title: String
    let value: String

    var id: String { value }

    static let all = [
        CommonTargetLanguage(title: "English", value: "English"),
        CommonTargetLanguage(title: "Simplified Chinese", value: "Simplified Chinese"),
        CommonTargetLanguage(title: "Traditional Chinese", value: "Traditional Chinese"),
        CommonTargetLanguage(title: "Japanese", value: "Japanese"),
        CommonTargetLanguage(title: "Korean", value: "Korean"),
        CommonTargetLanguage(title: "Spanish", value: "Spanish"),
        CommonTargetLanguage(title: "French", value: "French"),
        CommonTargetLanguage(title: "German", value: "German")
    ]
}
