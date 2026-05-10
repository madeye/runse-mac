import AppKit
import ApplicationServices

/// Reads selected text and selection bounds from the user's currently focused
/// UI element via the macOS Accessibility (AX) API. Reading from AX bypasses
/// the pasteboard entirely, so it does not trigger the "would like to access
/// data from other apps" privacy prompt — at the cost of a one-time
/// Accessibility permission grant.
enum AccessibilityReader {
    /// Returns true if this process currently holds Accessibility privilege.
    /// When `prompt` is true and the privilege is missing, macOS shows the
    /// standard "Open System Settings" dialog (no-op if already granted).
    @discardableResult
    static func ensureTrusted(prompt: Bool) -> Bool {
        // The HeaderDoc constant `kAXTrustedCheckOptionPrompt` is a global
        // `var` from a C header, which Swift 6 strict concurrency rejects.
        // The value is a stable CFString documented as
        // "AXTrustedCheckOptionPrompt", so we use the literal directly.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns the focused element's selected text, or nil if none / unavailable.
    static func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                &value) == .success,
              let text = value as? String,
              !text.isEmpty else { return nil }
        return text
    }

    /// Returns the on-screen bounds of the current selection in AppKit
    /// coordinates (origin lower-left of the primary screen). Returns nil if
    /// the focused element does not expose `kAXBoundsForRangeParameterizedAttribute`
    /// (Electron, Java Swing, custom-rendered editors).
    static func selectionBounds() -> NSRect? {
        guard let element = focusedElement() else { return nil }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &rangeRef) == .success,
              let rangeValue = rangeRef,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range),
              range.length > 0 else { return nil }

        guard let rangeArg = AXValueCreate(.cfRange, &range) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeArg,
                &boundsRef) == .success,
              let boundsValue = boundsRef,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect),
              rect.width > 0, rect.height > 0 else { return nil }

        return convertFromQuartz(rect)
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                system,
                kAXFocusedUIElementAttribute as CFString,
                &focused) == .success,
              let element = focused else { return nil }
        return (element as! AXUIElement)
    }

    /// AX returns rects in Quartz coordinates (origin top-left of the primary
    /// display). AppKit windows use bottom-left origin. Flip relative to the
    /// primary screen.
    private static func convertFromQuartz(_ rect: CGRect) -> NSRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let flippedY = primary.frame.height - rect.origin.y - rect.size.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }
}
