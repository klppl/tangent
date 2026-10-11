import AppKit
import ServiceManagement
import SwiftUI

/// How the helper is opened.
enum Trigger: String, CaseIterable {
    case doubleCommand, doubleOption, doubleControl, combo

    var modifier: Mods? {
        switch self {
        case .doubleCommand: return .command
        case .doubleOption: return .option
        case .doubleControl: return .control
        case .combo: return nil
        }
    }

    var label: String {
        modifier.map { "\($0.symbol) \($0.symbol)" } ?? "Egen"
    }

    private static let defaultsKey = "trigger"

    static func load() -> Trigger {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Trigger.init) ?? .doubleCommand
    }

    func save() { UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey) }
}

final class SettingsModel: ObservableObject {
    @Published private(set) var trigger = Trigger.load()
    @Published private(set) var hotKey = HotKey.load()
    @Published private(set) var recording = false
    @Published var error: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    let tapDetector = ModifierTapDetector()
    var onShowHelper: (() -> Void)?
    private var monitor: Any?

    var hotKeyDisplay: String { hotKey.display(KeyboardLayout()) }

    /// Short description for the menu, e.g. "⌘ ⌘" or "⌃⌥⌘K".
    var triggerDisplay: String { trigger == .combo ? hotKeyDisplay : trigger.label }

    func setTrigger(_ newValue: Trigger) {
        stopRecording(restore: false)
        error = nil
        trigger = newValue
        trigger.save()
        applyTrigger()
    }

    func applyTrigger() {
        tapDetector.modifier = trigger.modifier
        guard trigger == .combo else {
            HotKeyCenter.shared.unregister()
            return
        }
        if !HotKeyCenter.shared.register(hotKey) {
            error = "Kunde inte registrera \(hotKeyDisplay) – välj en annan kombination."
        }
    }

    func reset() {
        set(.standard)
    }

    func toggleRecording() {
        recording ? stopRecording(restore: true) : startRecording()
    }

    private func startRecording() {
        error = nil
        recording = true
        // Release the current hotkey so pressing it again can be recorded.
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func stopRecording(restore: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        if restore { applyTrigger() }
    }

    private func handle(_ event: NSEvent) {
        let mods = Mods(event.modifierFlags).subtracting(.fn)
        if event.keyCode == 0x35, mods.isEmpty {
            stopRecording(restore: true)
            return
        }
        let isFunctionKey = KeyboardLayout.specialNames[event.keyCode]?.hasPrefix("F") == true
        guard isFunctionKey || !mods.intersection([.command, .control]).isEmpty else {
            NSSound.beep()
            error = "Använd ⌘ eller ⌃ i kombinationen – ⌥- och ⇧-kombinationer används för att skriva tecken."
            return
        }
        stopRecording(restore: false)
        set(HotKey(keyCode: event.keyCode, mods: mods))
    }

    private func set(_ newValue: HotKey) {
        error = nil
        hotKey = newValue
        hotKey.save()
        applyTrigger()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Kunde inte ändra inloggningsobjekt: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Öppna teckenhjälpen med").font(.headline)
            Picker("", selection: Binding(get: { model.trigger }, set: { model.setTrigger($0) })) {
                ForEach(Trigger.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.trigger == .combo {
                HStack {
                    Button(action: model.toggleRecording) {
                        Text(model.recording ? "Tryck på en kombination…" : model.hotKeyDisplay)
                            .font(.system(size: 15, weight: .medium))
                            .frame(minWidth: 200)
                            .padding(.vertical, 4)
                    }
                    .controlSize(.large)
                    Button("Återställ", action: model.reset)
                        .disabled(model.recording)
                }
                Text(model.recording
                     ? "Tryck kombinationen du vill använda, eller esc för att avbryta."
                     : "Klicka på knappen och tryck en ny kombination.")
                    .font(.caption).foregroundColor(.secondary)
            } else if let mod = model.trigger.modifier {
                Text("Tryck \(mod.symbol) två gånger snabbt. Håll kvar andra trycket för att bara kika – hjälpen försvinner när du släpper.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle("Starta Tangent vid inloggning", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }))
            HStack {
                Spacer()
                Button("Visa teckenhjälpen") { model.onShowHelper?() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
