import AppKit
import RunseCore

/// Always-on Runse icon in the system menu bar. Click → menu with Refine /
/// Translate items that read selection from the previously-frontmost app via
/// Accessibility.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let trigger: AccessibilityTrigger

    init(trigger: AccessibilityTrigger) {
        self.trigger = trigger
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "wand.and.stars",
                                   accessibilityDescription: "Runse")
            button.image?.isTemplate = true
            button.toolTip = "Runse"
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let refine = NSMenuItem(title: "Refine Selected Text",
                                action: #selector(refine), keyEquivalent: "r")
        refine.target = self
        refine.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(refine)

        let translate = NSMenuItem(title: "Translate Selected Text",
                                   action: #selector(translate), keyEquivalent: "t")
        translate.target = self
        translate.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(translate)

        menu.addItem(.separator())

        let openMain = NSMenuItem(title: "Open Runse…",
                                  action: #selector(openMainWindow), keyEquivalent: "")
        openMain.target = self
        menu.addItem(openMain)

        let quit = NSMenuItem(title: "Quit Runse",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func refine() { trigger.runFromAccessibility(action: .refine) }
    @objc private func translate() { trigger.runFromAccessibility(action: .translate) }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Reveal the main SwiftUI WindowGroup window if any exists, otherwise
        // ask AppKit to (re)open it via the standard menu action.
        for window in NSApp.windows where window.canBecomeMain && window.contentViewController != nil {
            window.makeKeyAndOrderFront(nil)
            return
        }
        NSApp.sendAction(Selector(("showMainWindow:")), to: nil, from: nil)
    }
}
