// Preferences and the Settings window (right-click the open island → Settings…).
import AppKit
import ServiceManagement

enum Pref: String, CaseIterable {
    case showMascot, showMeetings, showNetSpeed, keepClips, checkForUpdates, clearShelfAfterDrag

    var title: String {
        switch self {
        case .showMascot: return "Show the robot"
        case .showMeetings: return "Show your next meeting"
        case .showNetSpeed: return "Show network speed"
        case .keepClips: return "Keep what you copy in Clips"
        case .checkForUpdates: return "Check for updates once a day"
        case .clearShelfAfterDrag: return "Take files off the shelf once dragged out"
        }
    }

    var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: rawValue) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: rawValue) }
    }

    /// Everything's on except clearing the shelf: by default files leave it only when they're moved.
    static func registerDefaults() {
        var d: [String: Any] = Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0 != .clearShelfAfterDrag) })
        d["focusMinutes"] = 25; d["breakMinutes"] = 5
        UserDefaults.standard.register(defaults: d)
    }
}

final class SettingsWindow: NSWindow {
    private let onChange: (Pref) -> Void
    private let claudeButton = NSButton(), codexButton = NSButton()
    private let claudeState = label("", 12, .regular, .secondaryLabelColor), codexState = label("", 12, .regular, .secondaryLabelColor)

    init(onChange: @escaping (Pref) -> Void, checkForUpdates: @escaping () -> Void) {
        self.onChange = onChange
        self.checkForUpdates = checkForUpdates
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

        // Focus timer lengths
        let focus = minutes("focusMinutes", [15, 20, 25, 30, 45, 50, 60]), rest = minutes("breakMinutes", [5, 10, 15, 20])
        let lengths = row([label("Focus", 13, .regular, .labelColor), focus, label("then a break of", 13, .regular, .labelColor), rest])

        // Coding agents
        let about = NSTextField(wrappingLabelWithString: "Shows when Claude Code or Codex is working, and lets you answer Claude Code's permission prompts from the notch. Connecting adds a few lines to their settings; disconnecting takes them out again.")
        about.font = .systemFont(ofSize: 12); about.textColor = .secondaryLabelColor
        about.preferredMaxLayoutWidth = 380
        for b in [claudeButton, codexButton] { b.bezelStyle = .rounded; b.target = self }
        claudeButton.action = #selector(toggleClaude); codexButton.action = #selector(toggleCodex)
        let claude = row([name("Claude Code"), claudeButton, claudeState]), codex = row([name("Codex"), codexButton, codexState])
        refreshAgents()

        // About
        let version = label("Notch Island \(Updater.current). Free and open source under the GPL-3.0.", 12, .regular, .secondaryLabelColor)
        let update = NSButton(title: "Check for Updates…", target: self, action: #selector(update(_:)))
        let sponsor = NSButton(title: "Sponsor…", target: self, action: #selector(sponsor(_:)))
        let links = row([update, sponsor])

        let stack = NSStackView(views: [heading("General"), login] + boxes
            + [heading("Focus timer"), lengths, heading("Coding agents"), about, claude, codex, heading("About"), version, links])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        contentView = stack
        setContentSize(stack.fittingSize)
        center()
    }

    private let checkForUpdates: () -> Void

    private func heading(_ s: String) -> NSView {
        let l = label(s, 13, .semibold, .labelColor)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 26))  // some space above each section
        l.frame.origin = NSPoint(x: 0, y: 0)
        l.sizeToFit()
        box.addSubview(l)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 26).isActive = true
        box.widthAnchor.constraint(equalToConstant: 380).isActive = true
        return box
    }

    /// A fixed-width name, so the buttons after it line up.
    private func name(_ s: String) -> NSView {
        let l = label(s, 13, .regular, .labelColor)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 90).isActive = true
        return l
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal; r.spacing = 8; r.alignment = .firstBaseline
        return r
    }

    private func minutes(_ key: String, _ options: [Int]) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        for m in options { p.addItem(withTitle: "\(m) min"); p.lastItem?.tag = m }
        p.selectItem(withTag: UserDefaults.standard.integer(forKey: key))
        p.identifier = NSUserInterfaceItemIdentifier(key)
        p.target = self; p.action = #selector(pickMinutes(_:))
        return p
    }

    @objc private func pickMinutes(_ p: NSPopUpButton) {
        guard let key = p.identifier?.rawValue, let m = p.selectedItem?.tag else { return }
        UserDefaults.standard.set(m, forKey: key)  // used from the next focus timer
    }

    private func refreshAgents() {
        let claude = AgentHooks.claudeConnected, codex = AgentHooks.codexConnected
        claudeButton.title = claude ? "Disconnect" : "Connect"
        claudeState.stringValue = claude ? "Connected. New sessions pick it up." : "Not connected"
        codexButton.title = codex ? "Disconnect" : "Connect"
        codexButton.isEnabled = AgentHooks.codexInstalled
        codexState.stringValue = !AgentHooks.codexInstalled ? "Not installed" : codex ? "Connected. Tells you when a turn finishes." : "Not connected"
    }

    @objc private func toggleClaude() { connect { try AgentHooks.setClaude(!AgentHooks.claudeConnected) } }
    @objc private func toggleCodex() { connect { try AgentHooks.setCodex(!AgentHooks.codexConnected) } }

    private func connect(_ change: () throws -> Void) {
        do { try change() } catch {
            let a = NSAlert(); a.messageText = "Couldn't change the agent's settings"; a.informativeText = error.localizedDescription
            a.beginSheetModal(for: self)
        }
        refreshAgents()
    }

    @objc private func update(_ b: NSButton) { checkForUpdates() }
    @objc private func sponsor(_ b: NSButton) { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/vipulpandey7860")!) }

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
