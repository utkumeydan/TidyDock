import AppKit
import Carbon.HIToolbox
import TidyDockCore

/// A button that records the next key combination pressed while it is active.
final class HotkeyRecorder: NSButton {
    var hotkey: Hotkey? { didSet { updateTitle() } }
    var onChange: ((Hotkey?) -> Void)?

    private var monitor: Any?
    private var isRecording = false { didSet { updateTitle() } }

    init(hotkey: Hotkey?) {
        self.hotkey = hotkey
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.stopRecording()
            case kVK_Delete, kVK_ForwardDelete:
                self.hotkey = nil
                self.onChange?(nil)
                self.stopRecording()
            default:
                // Ignore combinations without ⌘, ⌥ or ⌃ and keep listening.
                guard let hotkey = Hotkey(event: event) else { NSSound.beep(); return nil }
                self.hotkey = hotkey
                self.onChange?(hotkey)
                self.stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func updateTitle() {
        if isRecording {
            title = L("Type shortcut…")
        } else {
            title = hotkey?.displayString ?? L("Record Shortcut")
        }
    }
}
