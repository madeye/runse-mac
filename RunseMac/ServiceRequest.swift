import AppKit
import RunseCore

enum ServiceRequest {
    static func selectedText(from pasteboard: NSPasteboard) -> String? {
        for type in stringPasteboardTypes {
            if let text = pasteboard.string(forType: type), let normalized = normalized(text) {
                return normalized
            }
        }

        for type in attributedStringPasteboardTypes {
            if let data = pasteboard.data(forType: type),
               let attributed = try? NSAttributedString(data: data, options: [.documentType: documentType(for: type)], documentAttributes: nil),
               let normalized = normalized(attributed.string) {
                return normalized
            }
        }

        return nil
    }

    static func windowTitle(for action: TransformAction) -> String {
        switch action {
        case .refine:
            String(localized: "Runse - Refine Text")
        case .translate:
            String(localized: "Runse - Translate Text")
        case .pinyin:
            String(localized: "Runse - Pinyin")
        }
    }

    private static let stringPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .string,
        NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-plain-text"),
        NSPasteboard.PasteboardType("public.plain-text"),
        NSPasteboard.PasteboardType("public.text")
    ]

    private static let attributedStringPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .rtf,
        .rtfd,
        NSPasteboard.PasteboardType("NSRTFPboardType"),
        NSPasteboard.PasteboardType("NSRTFDPboardType"),
        NSPasteboard.PasteboardType("NSPasteboardTypeRTF"),
        NSPasteboard.PasteboardType("NSPasteboardTypeRTFD"),
        NSPasteboard.PasteboardType("public.html"),
        NSPasteboard.PasteboardType("NSHTMLPboardType"),
        NSPasteboard.PasteboardType("NSPasteboardTypeHTML")
    ]

    private static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func documentType(for pasteboardType: NSPasteboard.PasteboardType) -> NSAttributedString.DocumentType {
        if pasteboardType.rawValue.contains("HTML") || pasteboardType.rawValue.contains("html") {
            return .html
        }
        return pasteboardType == .rtfd || pasteboardType.rawValue.contains("RTFD") ? .rtfd : .rtf
    }
}
