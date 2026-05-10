import AppKit
import Carbon.HIToolbox

/// Registers system-wide Carbon hotkeys. Carbon hotkeys do not require
/// Accessibility permission to install; they are delivered to this process by
/// the system event dispatcher when the matching key combo fires globally.
@MainActor
final class HotkeyController {
    typealias Handler = @MainActor () -> Void

    private struct Registration {
        let id: UInt32
        let ref: EventHotKeyRef
        let handler: Handler
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() { installEventHandler() }

    // No deinit: this controller lives for the app's full lifetime. The
    // Carbon hotkey and event-handler registrations are torn down by the
    // system at process exit. A `@MainActor`-isolated `deinit` cannot touch
    // these non-Sendable C handles under Swift 6 strict concurrency.

    /// Register a global hotkey. `keyCode` is a Carbon virtual key code (e.g.
    /// `kVK_ANSI_R`); `modifiers` is a Carbon modifier mask (`cmdKey`,
    /// `shiftKey`, `optionKey`, `controlKey`).
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) -> Bool {
        let id = nextID; nextID += 1
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x52555345 /* 'RUSE' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr, let ref = hotKeyRef else { return false }
        registrations[id] = Registration(id: id, ref: ref, handler: handler)
        return true
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, eventRef, ctx -> OSStatus in
            guard let eventRef, let ctx else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let me = Unmanaged<HotkeyController>.fromOpaque(ctx).takeUnretainedValue()
            let id = hotKeyID.id
            DispatchQueue.main.async {
                me.registrations[id]?.handler()
            }
            return noErr
        }, 1, &spec, context, &eventHandler)
    }
}
