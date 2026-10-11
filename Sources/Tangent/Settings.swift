import AppKit
import ServiceManagement
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published private(set) var hotKey = HotKey.load()
    @Published private(set) var recording = false
    @Published var error: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    var onShowHelper: (() -> Void)?
    private var monitor: Any?

    var hotKeyDisplay: String { hotKey.display(KeyboardLayout()) }

    func applyHotKey() {
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
        if restore { applyHotKey() }
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
        applyHotKey()
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
            Text("Kortkommando för teckenhjälpen").font(.headline)
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
                 : "Klicka på knappen och tryck en ny kombination. Standard är ⌃⌥⌘K.")
                .font(.caption).foregroundColor(.secondary)
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
