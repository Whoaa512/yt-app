import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys (work while the app is unfocused) via Carbon
/// RegisterEventHotKey — no accessibility permission required.
/// All bindings use ⌃⌥⌘ to avoid stealing common shortcuts from other apps.
final class GlobalHotkeys {
    enum Action: UInt32, CaseIterable {
        case playPause = 1
        case seekBack = 2
        case seekForward = 3
        case speedUp = 4
        case speedDown = 5

        var keyCode: UInt32 {
            switch self {
            case .playPause: return UInt32(kVK_ANSI_P)
            case .seekBack: return UInt32(kVK_LeftArrow)
            case .seekForward: return UInt32(kVK_RightArrow)
            case .speedUp: return UInt32(kVK_UpArrow)
            case .speedDown: return UInt32(kVK_DownArrow)
            }
        }

        var label: String {
            switch self {
            case .playPause: return "⌃⌥⌘P Play/pause (global)"
            case .seekBack: return "⌃⌥⌘← Seek back 10s (global)"
            case .seekForward: return "⌃⌥⌘→ Seek forward 10s (global)"
            case .speedUp: return "⌃⌥⌘↑ Speed up (global)"
            case .speedDown: return "⌃⌥⌘↓ Speed down (global)"
            }
        }
    }

    var onAction: ((Action) -> Void)?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let instance = Unmanaged<GlobalHotkeys>.fromOpaque(userData).takeUnretainedValue()
            if let action = Action(rawValue: hotKeyID.id) {
                DispatchQueue.main.async { instance.onAction?(action) }
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x59544150), id: action.rawValue) // 'YTAP'
            RegisterEventHotKey(action.keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }

    func unregister() {
        for ref in hotKeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        hotKeyRefs.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    deinit { unregister() }
}
