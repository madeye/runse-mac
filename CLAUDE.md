# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project generation

The Xcode project is generated from `project.yml` via XcodeGen — never edit `RunseMac.xcodeproj` directly. After changing `project.yml`, target sources, Info.plist keys, or NSServices entries:

```sh
xcodegen generate
```

Targets: `RunseCore` (framework, the provider/prompt/keychain/settings layer) and `RunseMac` (the SwiftUI app + Services host) plus `RunseMacTests` (unit) and `RunseMacUITests` (UI). Swift 6, macOS 15 deployment target.

## Build / test

```sh
xcodebuild -scheme RunseMac -destination 'platform=macOS' build
xcodebuild -scheme RunseMac -destination 'platform=macOS' test
```

Run a single unit test:

```sh
xcodebuild -scheme RunseMac -destination 'platform=macOS' test \
  -only-testing:RunseMacTests/PromptRendererTests/<methodName>
```

The Notes context-menu UI tests are opt-in because they automate the Notes app and need Accessibility/Automation permission. Enable with the sentinel file, then disable:

```sh
touch /tmp/runse-notes-ui-tests-enabled
xcodebuild -scheme RunseMac -destination 'platform=macOS' test \
  -only-testing:RunseMacUITests/NotesContextMenuUITests
rm -f /tmp/runse-notes-ui-tests-enabled
```

## Local secrets / default API key

`Config/Local.example.xcconfig` is the committed config and is wired in for both Debug and Release. It conditionally `#include?`s `../../runse/Config/Local.xcconfig` so a sibling checkout of the iOS `runse` repo supplies the real `DEFAULT_NVIDIA_API_KEY_OBFUSCATED`. With no sibling, the build still works — the bundled obfuscated key is just empty and the app falls back to user-entered API keys.

The xcconfig value flows: `xcconfig` → `Info.plist` (`DefaultNVIDIAAPIKeyObfuscated`) → `RunseCore.Bootstrap` deobfuscates and seeds the Keychain on first launch. `SecretSeederTests` covers this path.

## Architecture

Data flow for the Services context-menu workflow:

1. macOS Services menu items are declared in `project.yml` under `NSServices` (`refineText` / `translateText` selectors, port `Runse`).
2. `RunseMacApp` (SwiftUI `@main`) builds a SwiftData `ModelContainer`, hands it to `AppServices.shared`, and registers `AppServices` as the `NSApp.servicesProvider`.
3. `AppServices.refineText` / `translateText` receive the `NSPasteboard`, parse it via `ServiceRequest` into a normalized payload (handles plain, RTF, RTFD, HTML send types listed in `project.yml`).
4. `TransformRequestBuilder` combines the parsed text with the user's selected provider/model/template from `SettingsStore` (UserDefaults for prefs, `KeychainStore` for API keys) and `PromptRenderer` (template substitution).
5. `TransformRunner` dispatches the request through `LLMProvider` (provider definitions and HTTP calls live in `RunseCore/LLMProvider.swift` and `Models.swift`).
6. A `TransformWindowView` is presented in a new `NSWindow` tracked by `AppServices.transformWindows`; the user runs the transform, sees the result, and copies back manually.

`ContentView` is the in-app Providers/Settings UI used outside the Services flow — it edits the same `SettingsStore` + `KeychainStore` that the service path reads.

`RunseCore` has no AppKit dependency and is the unit-tested core; `RunseMac` is the AppKit/SwiftUI host. Keep provider logic, prompt rendering, settings, and keychain access in `RunseCore` so `RunseMacTests` can exercise them without launching the app.

## Conventions

- When adding a Services action, update `NSServices` in `project.yml` (selector name, send types, default menu title), add the `@objc` handler in `AppServices`, regenerate, and add a `ServiceRequestTests` case.
- When adding a provider, extend `LLMProvider` and `Models` in `RunseCore`, then add a `ProviderRequestFactoryTests` case — don't reach into `RunseMac` for provider HTTP code.
