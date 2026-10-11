import AppKit
import Carbon

struct HotKey: Codable, Equatable {
    var keyCode: UInt16
    var mods: Mods

    /// ⌃⌥⌘K
    static let standard = HotKey(keyCode: 0x28, mods: [.control, .option, .command])

    private static let defaultsKey = "hotKey"

    static func load() -> HotKey {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let hotKey = try? JSONDecoder().decode(HotKey.self, from: data) else { return .standard }
        return hotKey
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func display(_ layout: KeyboardLayout) -> String {
        mods.parts.map(\.symbol).joined() + layout.keyName(keyCode, uppercase: true)
    }
}

/// Global hotkey via Carbon's RegisterEventHotKey — works without Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    @discardableResult
    func register(_ hotKey: HotKey) -> Bool {
        unregister()
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x5441_4E47), id: 1) // 'TANG'
        let status = RegisterEventHotKey(UInt32(hotKey.keyCode), hotKey.mods.carbon, id,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyCenter.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}
