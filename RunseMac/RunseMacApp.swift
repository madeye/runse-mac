import AppKit
import Carbon.HIToolbox
import RunseCore
import SwiftData
import SwiftUI

@main
struct RunseMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer

    init() {
        do {
            container = try Bootstrap.modelContainer()
            let modelContainer = container
            let keychainAccessGroup = KeychainAccessGroup.current()
            let seedValue = Bundle.main.obfuscatedDefaultNVIDIAAPIKey()
            Task { @MainActor in
                try? Bootstrap.seedDefaultsIfNeeded(context: modelContainer.mainContext)
                let keychain = KeychainStore(accessGroup: keychainAccessGroup)
                try? await SecretSeeder.seedDefaultNVIDIAIfNeeded(
                    secretStore: keychain,
                    buildSettingValue: seedValue
                )
            }
            AppServices.shared.configure(modelContainer: container)
        } catch {
            fatalError("Unable to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyController: HotkeyController?
    private var menuBarController: MenuBarController?
    private var popoverController: SelectionPopoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // macOS Services (right-click → Services → Runse Refine/Translate)
        NSApp.servicesProvider = AppServices.shared
        NSUpdateDynamicServices()

        // Accessibility-powered entry points. ensureTrusted(prompt: true)
        // surfaces the standard "open System Settings" dialog the first time;
        // a no-op once the user has granted the permission.
        AccessibilityReader.ensureTrusted(prompt: true)

        // (A) Global hotkeys. Defaults: ⌃⌥R refine, ⌃⌥T translate. The Carbon
        // event dispatcher delivers presses regardless of which app is
        // frontmost; no Accessibility permission needed for the hotkey itself.
        let hotkeys = HotkeyController()
        let modifiers = UInt32(controlKey | optionKey)
        hotkeys.register(keyCode: UInt32(kVK_ANSI_R), modifiers: modifiers) {
            AppServices.shared.runFromAccessibility(action: .refine)
        }
        hotkeys.register(keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers) {
            AppServices.shared.runFromAccessibility(action: .translate)
        }
        self.hotkeyController = hotkeys

        // (B) Always-on menu bar status item.
        self.menuBarController = MenuBarController(trigger: AppServices.shared)

        // (C) PopClip-style floating action bar. Honors the user's setting;
        // attaches AX observers lazily as the frontmost app changes.
        let settings = SettingsStore()
        let popover = SelectionPopoverController(trigger: AppServices.shared)
        popover.isEnabled = settings.selectionPopoverEnabled
        self.popoverController = popover

        NotificationCenter.default.addObserver(
            forName: .runseSelectionPopoverEnabledChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let enabled = note.object as? Bool else { return }
            Task { @MainActor in self?.popoverController?.isEnabled = enabled }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Stay alive after main window closes — the menu bar item, hotkeys,
        // and AX observers keep the app useful in the background.
        false
    }
}

private extension Bundle {
    func obfuscatedDefaultNVIDIAAPIKey() -> String? {
        guard let encoded = object(forInfoDictionaryKey: "DefaultNVIDIAAPIKeyObfuscated") as? String,
              !encoded.isEmpty,
              let data = Data(base64Encoded: encoded) else {
            return nil
        }

        let mask: [UInt8] = [0x5D, 0x19, 0xC7, 0x2E, 0xA4, 0x6B, 0x91, 0x38, 0xF2, 0x04, 0x7A, 0xD0, 0x63, 0xBC, 0x0F, 0xE5]
        let decoded = data.enumerated().map { index, byte in
            byte ^ mask[index % mask.count] ^ UInt8((index * 31 + 17) & 0xFF)
        }
        return String(bytes: decoded, encoding: .utf8)
    }
}
