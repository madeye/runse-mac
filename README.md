# Runse for macOS

> Refine and translate selected text in any macOS app, powered by your favorite LLM provider.

Runse for macOS is the desktop companion to [Runse for iOS](https://github.com/madeye/runse). Select text anywhere — Notes, Mail, Safari, Xcode, your editor of choice — and refine or translate it without copy-pasting into a separate window.

---

## Highlights

- **Three entry points, one transform window.** Pick whichever feels least invasive:
  - **Global hotkeys** — `⌃⌥R` to refine, `⌃⌥T` to translate.
  - **Floating action bar** — a small PopClip-style popover next to your selection.
  - **Services menu** — right-click on selected text → Services → Runse.
  - **Menu bar item** — wand icon for quick access.
- **Bring your own provider.** OpenAI Responses, Anthropic Messages, plus generic OpenAI- and Anthropic-compatible endpoints (NVIDIA NIM, DeepSeek, Kimi, OpenRouter, local llama.cpp/vLLM, …). Reasoning-model schemas (Qwen3, DeepSeek-R1) handled out of the box.
- **API keys live in the macOS Keychain.** Never written to disk in plain text.
- **No telemetry.** Your selected text only ever goes to the provider you configured.
- **Notarized + signed.** Stable Developer ID build means TCC permissions stick across launches.

## Installation

### Build from source (recommended for now)

```sh
brew install xcodegen
git clone https://github.com/madeye/runse-mac.git
cd runse-mac
xcodegen generate
open RunseMac.xcodeproj
# ⌘R in Xcode
```

Or via the command line:

```sh
xcodebuild -scheme RunseMac -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build build
cp -R build/Build/Products/Release/RunseMac.app /Applications/
```

### Pre-built releases

Notarized `.app` builds will be published on the [Releases](https://github.com/madeye/runse-mac/releases) page once the app reaches 1.0. Until then, build from source.

## Quick start

1. Launch **Runse** (`/Applications/RunseMac.app`).
2. macOS will prompt for **Accessibility** access — allow it. Required for the global hotkeys and floating bar to read selected text.
3. Open **Providers**. The bundled NVIDIA fallback works out of the box if you configured a default API key at build time; otherwise add your own:
   - **OpenAI** — Type: *OpenAI Responses* · Base URL: `https://api.openai.com` · Path: `/v1/responses` · Model: `gpt-4.1-mini`
   - **Anthropic** — Type: *Anthropic Messages* · Base URL: `https://api.anthropic.com` · Path: `/v1/messages` · Model: `claude-sonnet-4-5`
   - **NVIDIA NIM (Qwen3)** — Type: *OpenAI Compatible* · Base URL: `https://integrate.api.nvidia.com` · Path: `/v1/chat/completions` · Model: `qwen/qwen3.5-122b-a10b`
4. Paste your API key, hit **Save Key**, then **Test** to confirm.
5. Select text in any app and press `⌃⌥R` to refine, or `⌃⌥T` to translate.

## How it works

```
                        ┌───────────────────────────┐
                        │  Selection in another app │
                        └─────────────┬─────────────┘
                                      ▼
       ┌──────────┐       ┌──────────────────────────┐       ┌──────────────┐
       │ Hotkey   │       │   AccessibilityReader    │       │ Services menu│
       │ ⌃⌥R / ⌃⌥T│──────▶│  reads kAXSelectedText   │◀──────│   (pboard)   │
       └──────────┘       └─────────────┬────────────┘       └──────────────┘
                                        ▼
                          ┌─────────────────────────┐
                          │   AppServices presents  │
                          │  TransformWindowView    │
                          └─────────────┬───────────┘
                                        ▼
              TransformRunner → LLMProvider client → your provider
```

The `RunseCore` framework owns provider HTTP clients, prompt rendering, Keychain storage, and SwiftData models. It has no AppKit dependency and is fully unit-tested. The `RunseMac` app target wraps it in a SwiftUI host plus the four entry-point controllers (`HotkeyController`, `MenuBarController`, `SelectionPopoverController`, and the `NSServicesProvider`).

## Privacy

| Permission | Why it's asked | What happens if you skip it |
|---|---|---|
| **Accessibility** | Read selected text from any app via `AXUIElement` (no clipboard). | Hotkeys still register, but cannot read text from other apps. Floating bar disappears. Use the Services menu as a fallback. |
| **"Allow access to data from other apps"** | macOS gates Service-pasteboard reads in Sonoma+. Allow once per source app. | Services menu cannot read selection from that app; hotkeys still work. |
| **Login keychain access** | Read/write API keys for `Runse.ProviderAPIKey`. macOS may prompt the first time after re-signing the bundle. | Provider requests fail with "Missing API key." |

Selected text is sent only to the LLM provider configured in **Providers**. Runse has no analytics, no remote config, no first-party server.

## Tests

```sh
xcodebuild -scheme RunseMac -destination 'platform=macOS' test
```

The Notes context-menu UI tests are opt-in (they automate Notes and need Accessibility/Automation grants):

```sh
touch /tmp/runse-notes-ui-tests-enabled
xcodebuild -scheme RunseMac -destination 'platform=macOS' test \
  -only-testing:RunseMacUITests/NotesContextMenuUITests
rm -f /tmp/runse-notes-ui-tests-enabled
```

## Architecture

| Module | Role |
|---|---|
| `RunseCore` (framework, macOS-only AppKit-free) | `LLMProvider` clients (OpenAI Responses, Anthropic Messages, OpenAI-/Anthropic-compatible), `PromptRenderer`, `KeychainStore`, SwiftData `ProviderProfile` / `PromptTemplate` / `TransformHistory`. |
| `RunseMac` (app) | SwiftUI host, `AppServices` (Services provider + `AccessibilityTrigger`), `HotkeyController`, `MenuBarController`, `SelectionPopoverController`, `TransformWindowView`. |
| `RunseMacTests` | Unit tests for prompt rendering, request building, response parsing, secret seeding. |
| `RunseMacUITests` | Optional XCUITest suite that drives Notes through the Services menu. |

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen) — regenerate with `xcodegen generate` after changing `project.yml`, target sources, `Info.plist` keys, or `NSServices` entries.

See [`CLAUDE.md`](./CLAUDE.md) for development guidance, conventions, and signing notes.

## License

MIT — see [`LICENSE`](./LICENSE).

Built by [@madeye](https://github.com/madeye). Issues and pull requests welcome.
