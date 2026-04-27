import AppKit
import Carbon

struct HotkeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// Creates a shortcut from a key code and Carbon modifier bitmask.
    init(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers
    }

    /// Rehydrates a shortcut from the persisted `keyCode:modifiers` format.
    init?(serialized: String) {
        let parts = serialized.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt32(parts[1]) else {
            return nil
        }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var serialized: String {
        "\(keyCode):\(modifiers)"
    }

    var displayString: String {
        let modifierText = Self.modifierDisplay(modifiers)
        let keyText = Self.keyDisplay(keyCode: UInt16(truncatingIfNeeded: keyCode))
        return modifierText + keyText
    }

    /// Builds a shortcut from a keyboard event captured by the recorder field.
    static func from(event: NSEvent) -> HotkeyShortcut? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        return HotkeyShortcut(keyCode: event.keyCode, modifiers: modifiers)
    }

    /// Converts AppKit modifier flags to Carbon hotkey modifier flags.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    /// Converts a Carbon modifier mask into display glyphs.
    private static func modifierDisplay(_ modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result
    }

    /// Returns a user-facing key label for a key code.
    private static func keyDisplay(keyCode: UInt16) -> String {
        if let special = specialKeyMap[keyCode] {
            return special
        }
        if let scalar = scalarForANSIKeyCode(keyCode) {
            return String(scalar).uppercased()
        }
        let format = String(localized: "ShortcutsRecorderUnknownKeyFormat")
        return String(format: format, keyCode)
    }

    /// Resolves the printable scalar for an ANSI key using current layout data.
    private static func scalarForANSIKeyCode(_ keyCode: UInt16) -> UnicodeScalar? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self)
        guard let layoutPtr = CFDataGetBytePtr(layoutData) else { return nil }
        let keyboardLayout = layoutPtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }

        var deadKeyState: UInt32 = 0
        let maxLength: Int = 4
        var actualLength: Int = 0
        var chars = [UniChar](repeating: 0, count: maxLength)

        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &actualLength,
            &chars
        )

        guard status == noErr, actualLength > 0 else { return nil }
        return UnicodeScalar(chars[0])
    }

    private static let specialKeyMap: [UInt16: String] = [
        36: "↩",
        48: "⇥",
        49: "Space",
        51: "⌫",
        53: "⎋",
        76: "⌅",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        114: "Help",
        115: "Home",
        116: "PgUp",
        117: "⌦",
        118: "F4",
        119: "End",
        120: "F2",
        121: "PgDn",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]
}

final class GlobalHotkeyManager {
    enum Action: UInt32, CaseIterable {
        case startStop = 1
        case resetTimer = 2
        case lingerALittle = 3
        case snoozePrompt = 4

        var defaultsKey: String {
            switch self {
            case .startStop: return TimingSettingsKeys.hotkeyStartStop
            case .resetTimer: return TimingSettingsKeys.hotkeyResetTimer
            case .lingerALittle: return TimingSettingsKeys.hotkeyLingerALittle
            case .snoozePrompt: return TimingSettingsKeys.hotkeySnoozePrompt
            }
        }
    }

    private let signature: OSType = 0x4C4E4752 // "LNGR"
    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [Action: EventHotKeyRef] = [:]
    private let onAction: (Action) -> Void
    private let defaults: UserDefaults

    /// Registers the app-level hotkey event handler.
    init(defaults: UserDefaults = .standard, onAction: @escaping (Action) -> Void) {
        self.defaults = defaults
        self.onAction = onAction
        installEventHandler()
    }

    /// Unregisters all installed hotkeys and removes the event handler.
    deinit {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Re-registers hotkeys from user defaults.
    func reload() {
        unregisterAll()
        for action in Action.allCases {
            guard let raw = defaults.string(forKey: action.defaultsKey),
                  !raw.isEmpty,
                  let shortcut = HotkeyShortcut(serialized: raw) else {
                continue
            }
            register(shortcut: shortcut, for: action)
        }
    }

    /// Installs the Carbon event handler that receives hotkey press events.
    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotkeyEvent(eventRef)
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    /// Registers a single Carbon hotkey for the provided action.
    private func register(shortcut: HotkeyShortcut, for action: Action) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else { return }
        hotkeyRefs[action] = hotKeyRef
    }

    /// Unregisters every currently active Carbon hotkey.
    private func unregisterAll() {
        for (_, ref) in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
    }

    /// Resolves the pressed hotkey action and dispatches it to the callback.
    private func handleHotkeyEvent(_ eventRef: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == signature,
              let action = Action(rawValue: hotKeyID.id) else {
            return noErr
        }
        onAction(action)
        return noErr
    }
}
