# Runse for macOS

Runse for macOS exposes the core Runse refine and translate actions from the macOS Services context menu.

1. Build and launch `RunseMac`.
2. Configure a provider and API key in the Providers screen.
3. Select text in a compatible macOS app, open the context menu, then choose `Services > Runse Refine Text` or `Services > Runse Translate Text`.

The service opens a Runse transform window with the selected text. Run the transformation, then copy the result back to the source app.

macOS may ask whether `RunseMac` can access data from other apps when a Services action receives selected text from Notes or another app. Allow it for the context-menu workflow; Runse uses that access to read the selected text passed by the service request.

## Tests

Run the default unit and non-destructive UI test suite:

```sh
xcodebuild -scheme RunseMac -destination 'platform=macOS' test
```

Run the opt-in Notes context-menu UI tests:

```sh
touch /tmp/runse-notes-ui-tests-enabled
xcodebuild -scheme RunseMac -destination 'platform=macOS' test -only-testing:RunseMacUITests/NotesContextMenuUITests
rm -f /tmp/runse-notes-ui-tests-enabled
```

The Notes tests launch Notes, create temporary notes, open the selected-text context menu, and choose the Runse Services items. macOS may ask for Accessibility or Automation permission because the UI test runner controls Notes. It may also ask whether `RunseMac` can access data from other apps when Notes passes the selected text to the service. Allow Xcode, XCTest, the terminal app that runs `xcodebuild`, and `RunseMac` in System Settings > Privacy & Security.
