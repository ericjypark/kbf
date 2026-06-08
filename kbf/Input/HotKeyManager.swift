import AppKit
import Carbon.HIToolbox

/// Registers global hotkeys via Carbon `RegisterEventHotKey`. A SINGLE shared
/// event handler dispatches to the right callback by id — installing one handler
/// per hotkey doesn't work, because the first handler to return `noErr` consumes
/// the event before the others run.
final class HotKeyManager {
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x6b626631 // 'kbf1'

    init() { installHandler() }
    deinit {
        refs.values.forEach { UnregisterEventHotKey($0) }
        if let h = handlerRef { RemoveEventHandler(h) }
    }

    /// `modifiers` uses Carbon masks: cmdKey, shiftKey, optionKey, controlKey.
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        if let existing = refs[id] { UnregisterEventHotKey(existing); refs[id] = nil }
        actions[id] = action
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: signature, id: id),
                            GetEventDispatcherTarget(), 0, &ref)
        refs[id] = ref
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let this = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let action = mgr.actions[id.id] {
                DispatchQueue.main.async(execute: action)
            }
            return noErr
        }, 1, &spec, this, &handlerRef)
    }
}
