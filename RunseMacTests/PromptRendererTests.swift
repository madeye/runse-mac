import RunseCore
import XCTest

final class PromptRendererTests: XCTestCase {
    func testDefaultTranslatePromptIncludesSelectedTextAndTargetLanguage() {
        let template = PromptTemplate.builtIns().first { $0.action == .translate }!
        let prompt = PromptRenderer.render(
            template: template,
            context: PromptContext(selectedText: "Hello", action: .translate, targetLanguage: "Japanese")
        )

        XCTAssertTrue(prompt.user.contains("Hello"))
        XCTAssertTrue(prompt.user.contains("Japanese"))
        XCTAssertFalse(prompt.user.contains("{{selected_text}}"))
    }
}
