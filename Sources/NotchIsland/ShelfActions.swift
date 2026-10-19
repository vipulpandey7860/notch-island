// What you can do with files on the shelf: AirDrop, Share, Compress, Copy Path, Show in Finder.
import AppKit

enum ShelfAction {
    static func airDrop(_ urls: [URL]) {
        NSApp.activate()  // the AirDrop picker is a window of ours
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    static func share(_ urls: [URL], from view: NSView) {
        NSSharingServicePicker(items: urls).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    static func copyPaths(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    static func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    /// Zips the files next to the first one, like Finder's Compress, and hands back the archive.
    static func compress(_ urls: [URL], done: @escaping (URL?) -> Void) {
        guard let first = urls.first else { return }
        let dest = unused(first.deletingLastPathComponent()
            .appendingPathComponent(urls.count == 1 ? first.lastPathComponent : "Archive").appendingPathExtension("zip"))
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var source = first, scratch: URL?
            if urls.count > 1 {  // gather them in one folder; APFS clones them, so nothing is really copied
                let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                source = dir.appendingPathComponent("Archive")
                try? fm.createDirectory(at: source, withIntermediateDirectories: true)
                for u in urls { try? fm.copyItem(at: u, to: source.appendingPathComponent(u.lastPathComponent)) }
                scratch = dir
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, dest.path]
            try? p.run()
            p.waitUntilExit()
            if let scratch { try? fm.removeItem(at: scratch) }
            let ok = p.terminationStatus == 0
            DispatchQueue.main.async { done(ok ? dest : nil) }
        }
    }

    /// `name.zip`, or `name 2.zip`, `name 3.zip`… if that's taken.
    private static func unused(_ url: URL) -> URL {
        let base = url.deletingPathExtension().path, ext = url.pathExtension
        var candidate = url, n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

/// A menu item that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
