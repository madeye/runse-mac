import AppKit
import ApplicationServices
import RunseCore
import SwiftUI

/// PopClip-style floating action bar. Subscribes to AX selection-change
/// notifications on the frontmost app and shows a small floating panel near
/// the selection rect with Refine / Translate buttons.
///
/// Requires Accessibility permission; degrades gracefully (panel never
/// appears) in apps that do not expose `kAXSelectedTextChangedNotification` or
/// `kAXBoundsForRangeParameterizedAttribute`.
@MainActor
final class SelectionPopoverController {
    private let trigger: AccessibilityTrigger
    private var workspaceObserver: NSObjectProtocol?
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var panel: NSPanel?
    private var debounce: DispatchWorkItem?
    private var mouseUpMonitor: Any?

    /// Master switch — when false, the popover is fully detached from
    /// AX notifications and consumes no resources.
    var isEnabled: Bool = true {
        didSet {
            guard oldValue != isEnabled else { return }
            if isEnabled {
                attachToFrontmostApp()
                installMouseUpMonitor()
            } else {
                detach()
                removeMouseUpMonitor()
            }
        }
    }

    init(trigger: AccessibilityTrigger) {
        self.trigger = trigger
        observeWorkspace()
        attachToFrontmostApp()
        installMouseUpMonitor()
    }

    // No deinit: this controller lives for the lifetime of the app. The
    // workspace observer and AX run-loop source are reclaimed at process
    // teardown. A `@MainActor`-isolated `deinit` cannot touch the
    // non-Sendable observer reference under Swift 6 strict concurrency.

    private func observeWorkspace() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.attachToFrontmostApp() }
        }
    }

    private func attachToFrontmostApp() {
        guard isEnabled else { return }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        // Don't observe ourselves — would cause feedback loops with our own
        // window's selection changes.
        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier {
            hidePanel()
            return
        }
        let pid = frontmost.processIdentifier
        guard pid > 0, pid != observedPID else { return }
        detach()
        observedPID = pid
        hidePanel()

        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, _, _, ctx in
            guard let ctx else { return }
            let me = Unmanaged<SelectionPopoverController>.fromOpaque(ctx).takeUnretainedValue()
            // AX notifications also fire when a context menu opens (focus
            // moves to the menu). Never allow the ⌘C clipboard fallback from
            // this path — the synthetic keystroke would be consumed by the
            // tracking menu and dismiss it.
            DispatchQueue.main.async { me.handleSelectionChanged(allowClipboardFallback: false) }
        }, &observer)
        guard result == .success, let observer else { return }
        axObserver = observer

        let app = AXUIElementCreateApplication(pid)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app,
                                  kAXSelectedTextChangedNotification as CFString, ctx)
        AXObserverAddNotification(observer, app,
                                  kAXFocusedUIElementChangedNotification as CFString, ctx)
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer),
                           .commonModes)
    }

    private func detach() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(observer),
                                  .commonModes)
        }
        axObserver = nil
        observedPID = 0
    }

    /// Global mouse-up monitor — catches the end of a drag-select in apps
    /// where `kAXSelectedTextChangedNotification` does not fire (web browsers).
    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            // End of an explicit selection gesture — the one trigger where
            // the ⌘C clipboard fallback is safe (no menu is tracking; left
            // mouse-up inside a menu dismisses it before the debounce fires).
            Task { @MainActor in self?.handleSelectionChanged(allowClipboardFallback: true) }
        }
    }

    private func removeMouseUpMonitor() {
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
    }

    private func handleSelectionChanged(allowClipboardFallback: Bool) {
        // Coalesce bursts of selection-change notifications (typing, drag-select)
        // so we only query AX once the selection has settled. The last event in
        // a burst decides whether the clipboard fallback is allowed — a
        // drag-select ends with left mouse-up, so it keeps the fallback.
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.evaluateSelection(allowClipboardFallback: allowClipboardFallback) }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func evaluateSelection(allowClipboardFallback: Bool) {
        guard isEnabled,
              let text = AccessibilityReader.selectedText(allowClipboardFallback: allowClipboardFallback),
              text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            hidePanel()
            return
        }
        let bounds = AccessibilityReader.selectionBounds()
            ?? Self.boundsFromMouseLocation()
        showPanel(near: bounds, text: text)
    }

    /// Synthesise a zero-height rect at the current mouse cursor position.
    /// Used as a fallback when the focused element does not expose
    /// `kAXBoundsForRangeParameterizedAttribute` (web browsers, Electron,
    /// Java Swing).
    private static func boundsFromMouseLocation() -> NSRect {
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
    }

    private func showPanel(near bounds: NSRect, text: String) {
        let panel = panel ?? makePanel()
        self.panel = panel
        (panel.contentView as? NSHostingView<SelectionActionBar>)?.rootView =
            SelectionActionBar { [weak self] action in
                guard let self else { return }
                self.trigger.runFromAccessibility(action: action, prefetchedText: text)
                self.hidePanel()
            }

        let size = panel.frame.size
        var origin = NSPoint(x: bounds.minX, y: bounds.minY - size.height - 6)
        // If the panel would clip below the screen, place it above the selection.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: bounds.midX, y: bounds.midY)) })
            ?? NSScreen.main {
            if origin.y < screen.visibleFrame.minY {
                origin.y = bounds.maxY + 6
            }
            origin.x = min(max(origin.x, screen.visibleFrame.minX + 4),
                           screen.visibleFrame.maxX - size.width - 4)
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 248, height: 36),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: SelectionActionBar { _ in })
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    private func hidePanel() {
        debounce?.cancel()
        panel?.orderOut(nil)
    }
}

/// SwiftUI body of the floating selection action bar.
struct SelectionActionBar: View {
    let onAction: (TransformAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            actionButton(label: "Refine", systemImage: "wand.and.stars", action: .refine)
            Divider().frame(height: 18)
            actionButton(label: "Translate", systemImage: "character.bubble", action: .translate)
            Divider().frame(height: 18)
            actionButton(label: "Pinyin", systemImage: "textformat", action: .pinyin)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .fixedSize()
    }

    private func actionButton(label: String, systemImage: String, action: TransformAction) -> some View {
        Button(action: { onAction(action) }) {
            Label(label, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderless)
    }
}
