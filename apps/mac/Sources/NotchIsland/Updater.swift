// Updates from GitHub Releases. Once a day (and from the menu) it asks GitHub for the latest release, and if it's
// newer, a window shows what's new. Install and Relaunch downloads the zip, checks it was signed with the release
// key (Ed25519: the maintainer keeps the private half, the public half is NIUpdateKey in Info.plist), swaps the app
// in place and opens the new one. The app downloads it itself, so macOS doesn't block it the way it blocks apps
// downloaded in a browser.
import AppKit
import CryptoKit

struct Release {
    let version: String, notes: String
    let page: URL, zip: URL, signature: URL
}

final class Updater {
    static let feed = URL(string: "https://api.github.com/repos/vipulpandey7860/notch-island/releases/latest")!
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var key: Curve25519.Signing.PublicKey? { publicKey(Bundle.main.object(forInfoDictionaryKey: "NIUpdateKey") as? String) }
    private var window: UpdateWindow?

    enum Failure: LocalizedError {
        case noRelease, translocated, notWritable(URL), badSignature, wrongApp, unsigned
        var errorDescription: String? {
            switch self {
            case .noRelease: return "GitHub didn't have a release to offer."
            case .translocated: return "Move Notch Island to your Applications folder, open it from there, and try again."
            case .notWritable(let dir): return "Notch Island can't replace itself in \(dir.path). Download the new version instead."
            case .badSignature: return "The download wasn't signed with Notch Island's release key, so it wasn't installed."
            case .wrongApp: return "The download didn't contain the expected version of Notch Island, so it wasn't installed."
            case .unsigned: return "This copy was built without the release key, so it can't check updates. Download the new version instead."
            }
        }
    }

    /// Quietly shows the window when there's something new you haven't skipped. From the menu (`manual`), it also
    /// says when you're up to date or the check failed.
    @MainActor
    func check(manual: Bool = false) async {
        do {
            let r = try await Self.latest()
            if Self.isNewer(r.version, than: Self.current), manual || r.version != UserDefaults.standard.string(forKey: "skippedVersion") {
                show(r)
            } else if manual {
                Self.tell("You're up to date", "Notch Island \(Self.current) is the newest version.")
            }
        } catch {
            if manual { Self.tell("Couldn't check for updates", error.localizedDescription) }
        }
    }

    @MainActor
    private func show(_ r: Release) {
        window?.close()
        window = UpdateWindow(r) { w in
            Task { @MainActor in
                do {
                    guard let key = Self.key else { throw Failure.unsigned }
                    w.busy("Downloading Notch Island \(r.version)…")
                    try await Self.install(r, key: key)  // quits and reopens on success
                } catch {
                    w.failed(error.localizedDescription)
                }
            }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    static func tell(_ title: String, _ text: String) {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = title; a.informativeText = text
        a.runModal()
    }

    // MARK: Checking

    static func latest(from feed: URL = feed) async throws -> Release {
        var req = URLRequest(url: feed)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.noRelease }
        let tag = j["tag_name"] as? String ?? "", assets = j["assets"] as? [[String: Any]] ?? []
        func asset(_ suffix: String) -> URL? {
            assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init) }
        }
        guard let zip = asset(".zip"), let sig = asset(".zip.sig"), let page = (j["html_url"] as? String).flatMap(URL.init) else {
            throw Failure.noRelease
        }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, notes: j["body"] as? String ?? "",
                       page: page, zip: zip, signature: sig)
    }

    /// Compares dotted version numbers: 0.10.0 is newer than 0.9.2.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) {
            return (i < x.count ? x[i] : 0) > (i < y.count ? y[i] : 0)
        }
        return false
    }

    // MARK: Installing

    /// Downloads the release, checks its signature, puts it in place of `app`, and (normally) quits and reopens.
    static func install(_ r: Release, key: Curve25519.Signing.PublicKey, into app: URL = Bundle.main.bundleURL,
                        relaunch: Bool = true) async throws {
        let fm = FileManager.default, folder = app.deletingLastPathComponent()
        guard !app.path.contains("/AppTranslocation/") else { throw Failure.translocated }
        guard fm.isWritableFile(atPath: folder.path) else { throw Failure.notWritable(folder) }
        let (downloaded, _) = try await URLSession.shared.download(from: r.zip)
        let (signature, _) = try await URLSession.shared.data(from: r.signature)
        let zip = try Data(contentsOf: downloaded)
        guard verify(zip, signature: signature, key: key) else { throw Failure.badSignature }

        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)  // same disk as the app
        defer { try? fm.removeItem(at: dir) }
        let zipFile = dir.appendingPathComponent("update.zip")
        try zip.write(to: zipFile)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipFile.path, dir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard let new = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
              let info = NSDictionary(contentsOf: new.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == (Bundle(url: app)?.bundleIdentifier ?? Bundle.main.bundleIdentifier),
              info["CFBundleShortVersionString"] as? String == r.version else { throw Failure.wrongApp }
        _ = try fm.replaceItemAt(app, withItemAt: new)
        guard relaunch else { return }
        // Open the new copy once this one has quit
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try p.run()
        await MainActor.run { NSApp.terminate(nil) }
    }

    // MARK: Signing (release.sh uses these through the app's command line)

    static func publicKey(_ base64: String?) -> Curve25519.Signing.PublicKey? {
        base64.flatMap { Data(base64Encoded: $0) }.flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    /// A new key pair, base64: the private half (keep it secret), then the public half (for Info.plist).
    static func newKey() -> (secret: String, public: String) {
        let k = Curve25519.Signing.PrivateKey()
        return (k.rawRepresentation.base64EncodedString(), k.publicKey.rawRepresentation.base64EncodedString())
    }

    static func sign(_ data: Data, secret: String) throws -> String {
        guard let raw = Data(base64Encoded: secret.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw Failure.unsigned }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: raw).signature(for: data).base64EncodedString()
    }

    static func verify(_ data: Data, signature: Data, key: Curve25519.Signing.PublicKey) -> Bool {
        guard let sig = Data(base64Encoded: String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return key.isValidSignature(sig, for: data)
    }

    static func selfTest() {
        precondition(isNewer("0.10.0", than: "0.9.2") && isNewer("1.0", than: "0.9.9") && !isNewer("0.2.0", than: "0.2"), "versions")
        let k = newKey(), data = Data("Notch Island".utf8), sig = Data(try! sign(data, secret: k.secret).utf8)
        precondition(verify(data, signature: sig, key: publicKey(k.public)!), "signed")
        precondition(!verify(Data("Notch Island!".utf8), signature: sig, key: publicKey(k.public)!), "tampered")
        precondition(!verify(data, signature: sig, key: publicKey(newKey().public)!), "someone else's key")
    }
}

// MARK: - The window

/// "Notch Island 0.2.0 is out", what's new, and Install and Relaunch.
final class UpdateWindow: NSWindow {
    private let status = label("", 12, .regular, .secondaryLabelColor)
    private let spinner = NSProgressIndicator()
    private var buttons: [NSButton] = []
    private let release: Release
    private let install: (UpdateWindow) -> Void

    init(_ r: Release, install: @escaping (UpdateWindow) -> Void) {
        release = r
        self.install = install
        super.init(contentRect: NSRect(x: 0, y: 0, width: 500, height: 380), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Software Update"
        isReleasedWhenClosed = false
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 380))

        let robotView = NSView(frame: NSRect(x: 24, y: 300, width: 52, height: 52))
        robotView.wantsLayer = true; robotView.layer!.cornerRadius = 14; robotView.layer!.backgroundColor = NSColor.black.cgColor
        let robot = Robot()
        robot.layer.position = CGPoint(x: 26, y: 8)
        robot.layer.setAffineTransform(CGAffineTransform(scaleX: 1.5, y: 1.5))
        robot.loop([.wave1, .wave2], period: 0.8)
        robotView.layer!.addSublayer(robot.layer)
        let heading = label("Notch Island \(r.version) is out", 15, .semibold, .labelColor); put(heading, 92, 336, 380)
        let sub = label("You have \(Updater.current). Here's what's new:", 12, .regular, .secondaryLabelColor); put(sub, 92, 314, 380)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 76, width: 452, height: 210))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let notes = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        notes.isEditable = false; notes.textContainerInset = NSSize(width: 8, height: 8); notes.autoresizingMask = [.width]
        let md = (try? NSMutableAttributedString(markdown: r.notes.isEmpty ? "No notes for this release." : r.notes,
                                                 options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? NSMutableAttributedString(string: r.notes)
        md.addAttributes([.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.labelColor], range: NSRange(location: 0, length: md.length))
        notes.textStorage?.setAttributedString(md)
        scroll.documentView = notes

        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        spinner.frame = NSRect(x: 24, y: 50, width: 16, height: 16)
        put(status, 46, 58, 430)

        let skip = NSButton(title: "Skip This Version", target: self, action: #selector(skipVersion))
        let later = NSButton(title: "Later", target: self, action: #selector(close))
        let go = NSButton(title: "Install and Relaunch", target: self, action: #selector(installNow))
        go.keyEquivalent = "\r"
        skip.frame = NSRect(x: 18, y: 12, width: 150, height: 32)
        go.frame = NSRect(x: 322, y: 12, width: 160, height: 32)
        later.frame = NSRect(x: 232, y: 12, width: 92, height: 32)
        buttons = [skip, later, go]
        ([robotView, heading, sub, scroll, spinner, status] + buttons).forEach(v.addSubview)
        contentView = v
        center()
    }

    @objc private func skipVersion() {
        UserDefaults.standard.set(release.version, forKey: "skippedVersion")
        close()
    }

    @objc private func installNow() { install(self) }

    func busy(_ text: String) {
        status.stringValue = text
        status.textColor = .secondaryLabelColor
        spinner.startAnimation(nil)
        buttons.forEach { $0.isEnabled = false }
    }

    /// Says what went wrong, and offers the download page instead.
    func failed(_ message: String) {
        spinner.stopAnimation(nil)
        status.stringValue = message
        status.textColor = .systemRed
        status.cell?.wraps = true
        status.frame = NSRect(x: 24, y: 44, width: 452, height: 30)  // room for two lines
        buttons.forEach { $0.isEnabled = true }
        buttons[2].title = "Open Download Page"
        buttons[2].action = #selector(openPage)
    }

    @objc private func openPage() {
        NSWorkspace.shared.open(release.page)
        close()
    }
}
