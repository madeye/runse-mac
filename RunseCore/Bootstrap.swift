import Foundation
import SwiftData

public enum Bootstrap {
    static let schema = Schema([ProviderProfile.self, PromptTemplate.self, TransformHistory.self])

    /// Resolved on-disk store location: the shared app-group container when
    /// available (so the app and any future extensions share one database),
    /// otherwise the app's Application Support directory.
    static func defaultStoreURL(fileManager: FileManager = .default) -> URL? {
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: RunseConstants.appGroupID) {
            return groupURL.appending(path: "Runse.sqlite")
        }
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return appSupport.appending(path: "Runse.sqlite")
        }
        return nil
    }

    /// App entry point. Never throws for the on-disk path: a corrupt or
    /// schema-incompatible store is quarantined and recreated, and any
    /// remaining failure degrades to an in-memory store so the app launches
    /// instead of crash-looping at startup.
    public static func resilientModelContainer(fileManager: FileManager = .default) -> ModelContainer {
        if let storeURL = defaultStoreURL(fileManager: fileManager) {
            do {
                return try modelContainer(at: storeURL, fileManager: fileManager)
            } catch {
                // Even a fresh on-disk store could not be opened (e.g. an
                // unwritable container). Fall through to in-memory rather than
                // leaving the user stuck in a permanent launch crash loop.
            }
        }
        if let inMemory = try? inMemoryContainer() {
            return inMemory
        }
        // An in-memory container with a valid schema effectively never fails;
        // reaching here means the schema itself is invalid — a build-time bug
        // that surfaces in tests/CI, not on a user's machine.
        fatalError("RunseCore schema is invalid; cannot create any ModelContainer.")
    }

    /// Opens the store at `storeURL`. If the existing store is corrupt or
    /// schema-incompatible (the historical launch-crash cause), it quarantines
    /// the bad files and retries once with a fresh store instead of throwing.
    public static func modelContainer(
        at storeURL: URL,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            quarantineStore(at: storeURL, fileManager: fileManager)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    /// In-memory container — used by tests and as the last-resort fallback so
    /// the app stays usable (without persistence) rather than crash-looping.
    public static func inMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Backwards-compatible explicit builder. `inMemory: true` yields an
    /// in-memory store; otherwise opens (and recovers) the default on-disk store.
    public static func modelContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try inMemoryContainer()
        }
        guard let storeURL = defaultStoreURL() else {
            return try inMemoryContainer()
        }
        return try modelContainer(at: storeURL)
    }

    /// Moves the store and its `-wal`/`-shm` sidecar files aside so a fresh
    /// store can be created in their place. Best-effort: individual move
    /// failures are ignored because the caller's retry (and ultimately the
    /// in-memory fallback) handles a still-unusable location.
    static func quarantineStore(at storeURL: URL, fileManager: FileManager) {
        let token = UUID().uuidString
        let directory = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            let source = directory.appending(path: name + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = directory.appending(path: "\(name).corrupt-\(token)\(suffix)")
            try? fileManager.moveItem(at: source, to: destination)
        }
    }

    @MainActor public static func seedDefaultsIfNeeded(context: ModelContext) throws {
        let defaultProfileID = RunseConstants.defaultProfileID
        var providerDescriptor = FetchDescriptor<ProviderProfile>(predicate: #Predicate { $0.id == defaultProfileID })
        providerDescriptor.fetchLimit = 1
        let defaultProvider = ProviderProfile.defaultNVIDIA()
        if let existingProvider = try context.fetch(providerDescriptor).first {
            existingProvider.name = defaultProvider.name
            existingProvider.kind = defaultProvider.kind
            existingProvider.baseURL = defaultProvider.baseURL
            existingProvider.chatEndpoint = defaultProvider.chatEndpoint
            existingProvider.model = defaultProvider.model
            existingProvider.extraHeadersJSON = defaultProvider.extraHeadersJSON
            existingProvider.isDefault = true
            existingProvider.updatedAt = .now
        } else {
            context.insert(defaultProvider)
        }

        for template in PromptTemplate.builtIns() {
            let templateID = template.id
            var descriptor = FetchDescriptor<PromptTemplate>(predicate: #Predicate { $0.id == templateID })
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                if existing.isBuiltIn {
                    existing.name = template.name
                    existing.action = template.action
                    existing.systemTemplate = template.systemTemplate
                    existing.userTemplate = template.userTemplate
                    existing.updatedAt = .now
                }
            } else {
                context.insert(template)
            }
        }
        try context.save()
    }
}

public enum TextExcerpt {
    public static func make(_ text: String, maxLength: Int = 240) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "..."
    }
}
