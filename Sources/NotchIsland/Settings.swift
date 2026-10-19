// Preferences and the Settings window (right-click the open island → Settings…).
import AppKit
import ServiceManagement

enum Pref: String, CaseIterable {
    case showMascot, showMeetings, showNetSpeed, clearShelfAfterDrag

    var title: String {
        switch self {
        case .showMascot: return "Show the robot"
        case .showMeetings: return "Show your next meeting"
        case .showNetSpeed: return "Show network speed"
        case .clearShelfAfterDrag: return "Take files off the shelf once dragged out"
        }
    }

    var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: rawValue) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: rawValue) }
    }

    /// Everything's on except clearing the shelf: by default files leave it only when they're moved.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0 != .clearShelfAfterDrag) }))
    }
}

final class SettingsWindow: NSWindow {
    private let onChange: (Pref) -> Void

    init(onChange: @escaping (Pref) -> Void) {
        self.onChange = onChange
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Notch Island Settings"
        isReleasedWhenClosed = false
        let login = NSButton(checkboxWithTitle: "Open at login", target: self, action: #selector(toggleLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let boxes = Pref.allCases.map { p -> NSButton in
            let b = NSButton(checkboxWithTitle: p.title, target: self, action: #selector(toggle(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(p.rawValue)
            b.state = p.isOn ? .on : .off
            return b
        }
        let stack = NSStackView(views: [login] + boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        contentView = stack
        setContentSize(stack.fittingSize)
        center()
    }

    @objc private func toggle(_ b: NSButton) {
        guard let id = b.identifier?.rawValue, let p = Pref(rawValue: id) else { return }
        p.isOn = b.state == .on
        onChange(p)
    }

    @objc private func toggleLogin(_ b: NSButton) {
        do {
            if b.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        // macOS may want you to allow it in System Settings first
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        b.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
