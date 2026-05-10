import AppKit
import RunseCore
@testable import RunseMac
import XCTest

final class ServiceRequestTests: XCTestCase {
    func testSelectedTextTrimsPasteboardString() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("  Refine this sentence. \n", forType: .string)

        XCTAssertEqual(ServiceRequest.selectedText(from: pasteboard), "Refine this sentence.")
    }

    func testSelectedTextRejectsEmptyPasteboardString() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("   \n\t", forType: .string)

        XCTAssertNil(ServiceRequest.selectedText(from: pasteboard))
    }

    func testSelectedTextReadsUTF8PlainTextType() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("  Translate this. ", forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))

        XCTAssertEqual(ServiceRequest.selectedText(from: pasteboard), "Translate this.")
    }

    func testSelectedTextReadsRTFSelection() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let attributed = NSAttributedString(string: "  Notes selected text. ")
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .rtf)

        XCTAssertEqual(ServiceRequest.selectedText(from: pasteboard), "Notes selected text.")
    }

    func testSelectedTextReadsHTMLSelection() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let html = Data("<p>  Notes <strong>HTML</strong> text. </p>".utf8)
        pasteboard.clearContents()
        pasteboard.setData(html, forType: NSPasteboard.PasteboardType("public.html"))

        XCTAssertEqual(ServiceRequest.selectedText(from: pasteboard), "Notes HTML text.")
    }

    func testWindowTitleMatchesServiceAction() {
        XCTAssertEqual(ServiceRequest.windowTitle(for: .refine), "Runse - Refine Text")
        XCTAssertEqual(ServiceRequest.windowTitle(for: .translate), "Runse - Translate Text")
    }
}
