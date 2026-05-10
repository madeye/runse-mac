import AppKit
import XCTest

@MainActor
final class NotesContextMenuUITests: XCTestCase {
    nonisolated private static let optInMarkerPath = "/tmp/runse-notes-ui-tests-enabled"
    private var noteText = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard Self.shouldRunNotesTests else {
            let optInMarkerPath = Self.optInMarkerPath
            throw XCTSkip("Create \(optInMarkerPath) to run the Notes context-menu UI tests. They require macOS Accessibility/Automation permission and modify the local Notes app.")
        }
    }

    nonisolated private static var shouldRunNotesTests: Bool {
        ProcessInfo.processInfo.environment["RUNSE_NOTES_UI_TESTS"] == "1" ||
            FileManager.default.fileExists(atPath: optInMarkerPath)
    }

    func testNotesContextMenuOpensRunseRefineService() throws {
        let runse = XCUIApplication()
        runse.launch()

        let notes = XCUIApplication(bundleIdentifier: "com.apple.Notes")
        notes.launch()
        XCTAssertTrue(notes.wait(for: .runningForeground, timeout: 10), "Notes did not launch.")
        defer {
            deleteCurrentNote(in: notes)
            runse.terminate()
        }

        createTemporaryNote(in: notes)
        selectNoteText(in: notes)
        let contextRoot = try openContextMenuForSelectedText(in: notes)
        chooseRunseService(named: "Runse Refine Text", contextRoot: contextRoot, notes: notes)

        XCTAssertTrue(runse.wait(for: .runningForeground, timeout: 10), "Runse did not become foreground after choosing the service.")
        let window = runse.windows["Runse - Refine Text"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Choosing Services > Runse > Refine Text should open the Runse refine window.")
        XCTAssertTrue(window.staticTexts[noteText].waitForExistence(timeout: 5), "The Runse transform window should contain the selected Notes text.")
    }

    func testNotesContextMenuOpensRunseTranslateService() throws {
        let runse = XCUIApplication()
        runse.launch()

        let notes = XCUIApplication(bundleIdentifier: "com.apple.Notes")
        notes.launch()
        XCTAssertTrue(notes.wait(for: .runningForeground, timeout: 10), "Notes did not launch.")
        defer {
            deleteCurrentNote(in: notes)
            runse.terminate()
        }

        createTemporaryNote(in: notes)
        selectNoteText(in: notes)
        let contextRoot = try openContextMenuForSelectedText(in: notes)
        chooseRunseService(named: "Runse Translate Text", contextRoot: contextRoot, notes: notes)

        XCTAssertTrue(runse.wait(for: .runningForeground, timeout: 10), "Runse did not become foreground after choosing the service.")
        let window = runse.windows["Runse - Translate Text"]
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Choosing Services > Runse > Translate Text should open the Runse translate window.")
        XCTAssertTrue(window.staticTexts[noteText].waitForExistence(timeout: 5), "The Runse transform window should contain the selected Notes text.")
    }

    private func createTemporaryNote(in notes: XCUIApplication) {
        noteText = "Runse UI test \(UUID().uuidString)"
        notes.typeKey("n", modifierFlags: [.command])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(noteText, forType: .string)
        notes.typeKey("v", modifierFlags: [.command])
    }

    private func deleteCurrentNote(in notes: XCUIApplication) {
        notes.activate()
        guard notes.wait(for: .runningForeground, timeout: 5) else { return }
        notes.typeKey(.delete, modifierFlags: [.command])

        let deleteButtons = [
            notes.buttons["Delete Note"],
            notes.buttons["Delete"],
            notes.sheets.buttons["Delete Note"],
            notes.sheets.buttons["Delete"]
        ]
        firstExistingElement(deleteButtons)?.click()
    }

    private func selectNoteText(in notes: XCUIApplication) {
        let editor = firstExistingElement([
            notes.textViews.firstMatch,
            notes.scrollViews.firstMatch,
            notes.windows.firstMatch
        ])
        editor?.click()
        notes.typeKey("a", modifierFlags: [.command])
    }

    private func openContextMenuForSelectedText(in notes: XCUIApplication) throws -> XCUIElement {
        let editor = firstExistingElement([
            notes.textViews.firstMatch,
            notes.scrollViews.firstMatch,
            notes.windows.firstMatch
        ])
        let contextRoot = try XCTUnwrap(editor, "Could not find a Notes editor or window to open the context menu.")
        contextRoot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        return contextRoot
    }

    private func chooseRunseService(named serviceName: String, contextRoot: XCUIElement, notes: XCUIApplication) {
        let directService = contextRoot.menuItems[serviceName]
        if directService.waitForExistence(timeout: 3) {
            directService.click()
            return
        }

        let runseMenu = contextRoot.menuItems["Runse"]
        if runseMenu.waitForExistence(timeout: 3) {
            runseMenu.hover()
            let service = notes.menuItems[serviceName]
            XCTAssertTrue(service.waitForExistence(timeout: 3), "Runse service '\(serviceName)' was not available in the context menu.")
            service.click()
            return
        }

        let servicesMenu = contextRoot.menuItems["Services"]
        XCTAssertTrue(servicesMenu.waitForExistence(timeout: 3), "Notes context menu did not expose Services for the selected text.")
        servicesMenu.hover()

        let nestedRunseMenu = notes.menuItems["Runse"]
        if nestedRunseMenu.waitForExistence(timeout: 3) {
            nestedRunseMenu.hover()
        }

        let service = notes.menuItems[serviceName]
        XCTAssertTrue(service.waitForExistence(timeout: 3), "Runse service '\(serviceName)' was not available under Services.")
        service.click()
    }

    private func firstExistingElement(_ elements: [XCUIElement]) -> XCUIElement? {
        elements.first { $0.waitForExistence(timeout: 2) }
    }
}
