import AppKit
import RunseCore
import SwiftData
import SwiftUI

/// Anything that can resolve "user wants to transform their current selection"
/// into an open transform window. Implemented by `AppServices` and used by the
/// hotkey, menu-bar, and selection-popover controllers so they don't need to
/// know about model containers or window plumbing.
@MainActor
protocol AccessibilityTrigger: AnyObject {
    func runFromAccessibility(action: TransformAction, prefetchedText: String?)
}

extension AccessibilityTrigger {
    func runFromAccessibility(action: TransformAction) {
        runFromAccessibility(action: action, prefetchedText: nil)
    }
}

@MainActor
final class AppServices: NSObject, AccessibilityTrigger {
    static let shared = AppServices()

    private var modelContainer: ModelContainer?
    private var transformWindows: [NSWindow] = []

    private override init() {}

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - macOS Services entry points

    @objc func refineText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        openFromPasteboard(action: .refine, pasteboard: pasteboard, error: error)
    }

    @objc func translateText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        openFromPasteboard(action: .translate, pasteboard: pasteboard, error: error)
    }

    @objc func pinyinText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        openFromPasteboard(action: .pinyin, pasteboard: pasteboard, error: error)
    }

    private func openFromPasteboard(action: TransformAction, pasteboard: NSPasteboard, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let selectedText = ServiceRequest.selectedText(from: pasteboard) else {
            error.pointee = "Runse could not read selected text."
            return
        }
        guard modelContainer != nil else {
            error.pointee = "Runse is still starting up."
            return
        }
        presentTransformWindow(action: action, selectedText: selectedText)
    }

    // MARK: - Accessibility entry point

    func runFromAccessibility(action: TransformAction, prefetchedText: String? = nil) {
        let text = prefetchedText ?? AccessibilityReader.selectedText()
        guard let text, !text.isEmpty else {
            NSSound.beep()
            return
        }
        guard modelContainer != nil else { return }
        presentTransformWindow(action: action, selectedText: text)
    }

    // MARK: - Window plumbing (shared)

    private func presentTransformWindow(action: TransformAction, selectedText: String) {
        guard let modelContainer else { return }

        let view = TransformWindowView(selectedText: selectedText, initialAction: action) { [weak self] window in
            self?.close(window: window)
        }
        .modelContainer(modelContainer)

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = ServiceRequest.windowTitle(for: action)
        window.setContentSize(NSSize(width: 620, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        transformWindows.append(window)
    }

    private func close(window: NSWindow?) {
        guard let window else { return }
        window.close()
        transformWindows.removeAll { $0 === window }
    }
}
