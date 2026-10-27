import AppKit
import Carbon.HIToolbox
import DKBSecretCore
import Observation

/// A key combination for the global shortcut: Carbon key code + Carbon
/// modifier mask, stored as two settings.
struct HotKey: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// ⌥⌘S, the default shortcut.
    static let `default` = HotKey(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(optionKey | cmdKey))

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// From an `NSEvent` in the recorder. `nil` when the press has no
    /// ⌘/⌥/⌃ — a bare letter must never become a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
    }

    /// "⌥⌘S" for the Settings row.
    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(keyCode)] { return name }
        // Letters/digits/punctuation: ask the current keyboard layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let layout = unsafeBitCast(CFDataGetBytePtr(unsafeBitCast(layoutData, to: CFData.self)), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                    UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    // MARK: Persistence

    static let keyCodeSetting = "hotkey.keyCode"
    static let modifiersSetting = "hotkey.modifiers"

    static func load(from settings: SettingsRepository) -> HotKey {
        guard let code = (try? settings.get(keyCodeSetting)).flatMap(UInt32.init),
              let mods = (try? settings.get(modifiersSetting)).flatMap(UInt32.init)
        else { return .default }
        return HotKey(keyCode: code, carbonModifiers: mods)
    }

    func save(to settings: SettingsRepository) {
        try? settings.set(Self.keyCodeSetting, String(keyCode))
        try? settings.set(Self.modifiersSetting, String(carbonModifiers))
    }
}

/// Registers the global shortcut with Carbon's `RegisterEventHotKey` — no
/// Accessibility permission, works inside the sandbox (tested). One
/// handler for the app; the registered combination can be swapped at
/// runtime from Settings.
@MainActor
@Observable
final class HotKeyManager {
    private(set) var hotKey: HotKey
    /// Carbon refused the combination — another app holds it globally.
    private(set) var registrationFailed = false
    private let settings: SettingsRepository
    private let onPress: () -> Void
    private var registration: EventHotKeyRef?
    private var handlerInstalled = false

    /// Carbon calls a C function; it can't capture, so it finds us here.
    nonisolated(unsafe) private static var current: HotKeyManager?

    init(settings: SettingsRepository, onPress: @escaping () -> Void) {
        self.settings = settings
        self.onPress = onPress
        hotKey = HotKey.load(from: settings)
    }

    func start() {
        Self.current = self
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in HotKeyManager.current?.onPress() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        register()
    }

    func update(_ newValue: HotKey) {
        hotKey = newValue
        newValue.save(to: settings)
        register()
    }

    private func register() {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        let id = EventHotKeyID(signature: OSType(0x444B4253), id: 1) // "DKBS"
        var ref: EventHotKeyRef?
        if RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr {
            registration = ref
            registrationFailed = false
        } else {
            registrationFailed = true
        }
    }
}
