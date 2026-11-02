import AppKit

// MARK: - Now playing

struct Track {
    var title = "", artist = "", album = "", bundle = "", app = ""
    var duration = 0.0, elapsed = 0.0, ts = 0.0, rate = 0.0
    var artwork: NSImage?  // album art, or the player app's icon when there is none
    var artID = ""         // which track `artwork` belongs to
    var accent = NSColor.white

    var id: String { [bundle, title, artist, album].joined(separator: "|") }
    var playing: Bool { rate > 0 }
    /// Playback position right now, extrapolated from the last report.
    var position: Double {
        let p = elapsed + (playing ? (Date().timeIntervalSince1970 - ts) * rate : 0)
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

/// System-wide now playing. Since macOS 15.4 MediaRemote only answers Apple-signed processes, so
/// /usr/bin/perl loads NowPlayingHelper.dylib (Sources/NowPlayingHelper), which streams JSON lines back and takes commands.
final class NowPlaying {
    private(set) var track: Track?
    var onChange: (_ newTrack: Bool) -> Void = { _ in }
    private var input: FileHandle?
    private var buffer = Data()
    private var clearing: Task<Void, Never>?
    private var hold: (playing: Bool, until: Date)?  // what the user just asked for, until the player catches up
    private var raw: Track?                          // the latest report, before smoothing
    private var pauseCheck: Task<Void, Never>?
    private static let script = """
        use DynaLoader;
        my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        DynaLoader::dl_install_xsub("main::run", DynaLoader::dl_find_symbol($h, "notchisland_nowplaying_run"));
        run();
        """

    // REVIEW: Apple has said macOS will stop shipping scripting runtimes like perl. When /usr/bin/perl goes,
    // this needs another Apple-signed host that can load our code (osascript can't: arm64e platform binary).
    func start() {
        guard let lib = Bundle.main.path(forResource: "NowPlayingHelper", ofType: "dylib") else { return }
        let p = Process(), out = Pipe(), inp = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.script, lib]
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.receive(d) }
        }
        let started = Date()
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.track != nil { self.track = nil; self.onChange(true) }
                // REVIEW: a helper that ran a while is restarted; one that dies at once (no perl, API closed) stays
                // off and now playing just disappears. Tell the user instead?
                if Date().timeIntervalSince(started) > 10 { after(2) { self.start() } }
            }
        }
        do { try p.run() } catch { return }
        input = inp.fileHandleForWriting
    }

    private func receive(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { apply(obj) }
        }
    }

    private func apply(_ d: [String: Any]) {
        guard let title = d["title"] as? String else {
            // {} = nothing is playing. Players blink this between states, so only believe it after a second.
            clearing?.cancel()
            clearing = after(1) { [weak self] in
                guard let self, self.track != nil else { return }
                self.track = nil
                self.onChange(true)
            }
            return
        }
        clearing?.cancel()
        let num = { (k: String) in (d[k] as? NSNumber)?.doubleValue ?? 0 }
        let oldID = track?.id
        var t = track ?? Track()
        let bundle = d["bundle"] as? String ?? ""
        if bundle != t.bundle || t.app.isEmpty {
            t.app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                .map { FileManager.default.displayName(atPath: $0.path) } ?? ""
        }
        t.title = title
        t.artist = d["artist"] as? String ?? ""
        t.album = d["album"] as? String ?? ""
        t.bundle = bundle
        t.duration = num("duration"); t.elapsed = num("elapsed"); t.ts = num("ts"); t.rate = num("rate")
        if let art = d["art"] as? String, let img = Data(base64Encoded: art).flatMap(NSImage.init(data:)) {
            t.artwork = img; t.accent = accentColor(img); t.artID = t.id  // sent once per track
        } else if t.artwork == nil {
            t.artwork = appIcon(bundle); t.accent = accentColor(t.artwork)
        } else if t.id != oldID {
            // New track, its art not here yet: keep the old picture briefly, then fall back to the app icon
            let id = t.id
            after(1.5) { [weak self] in
                guard let self, var cur = self.track, cur.id == id, cur.artID != id else { return }
                cur.artwork = appIcon(cur.bundle); cur.accent = accentColor(cur.artwork); cur.artID = id
                self.track = cur
                self.onChange(false)
            }
        }
        raw = t
        smoothPlaying(&t)
        track = t
        onChange(t.id != oldID)
    }

    /// Players send stale or split-second states around play/pause and track changes; smooth them out.
    private func smoothPlaying(_ t: inout Track) {
        if let h = hold, Date() < h.until {
            if t.playing == h.playing { hold = nil } else { force(&t, playing: h.playing) }
            return
        }
        hold = nil
        if t.playing { pauseCheck?.cancel(); pauseCheck = nil; return }
        // A pause straight after playing must last 0.6s to count (players blip one between tracks)
        guard track?.playing == true else { return }
        force(&t, playing: true)
        guard pauseCheck == nil else { return }
        pauseCheck = after(0.6) { [weak self] in
            guard let self else { return }
            self.pauseCheck = nil
            guard let r = self.raw, !r.playing, var cur = self.track, cur.playing else { return }
            cur.rate = 0; cur.elapsed = r.elapsed; cur.ts = r.ts
            self.track = cur
            self.onChange(false)
        }
    }

    private func force(_ t: inout Track, playing: Bool) {
        let pos = t.position
        t.rate = playing ? 1 : 0; t.elapsed = pos; t.ts = Date().timeIntervalSince1970
    }

    private func send(_ cmd: String) { try? input?.write(contentsOf: Data((cmd + "\n").utf8)) }

    // Optimistic updates so the UI reacts instantly; the helper's next report corrects them.
    func toggle() {
        send("toggle")
        guard var t = track else { return }
        hold = (!t.playing, Date().addingTimeInterval(1.5))
        pauseCheck?.cancel(); pauseCheck = nil
        force(&t, playing: !t.playing)
        track = t
        onChange(false)
    }
    func next() { send("next") }
    func prev() { send("prev") }
    func seek(_ seconds: Double) {
        send("seek \(seconds)")
        guard var t = track else { return }
        t.elapsed = seconds; t.ts = Date().timeIntervalSince1970
        track = t
        onChange(false)
    }
}

func appIcon(_ bundle: String) -> NSImage? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
}

/// Saturation-weighted average colour of an image, lifted so it reads on black.
func accentColor(_ img: NSImage?) -> NSColor {
    guard let img, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
                                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return .white }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: 8, height: 8))
    NSGraphicsContext.restoreGraphicsState()
    var r = 0.0, g = 0.0, b = 0.0, total = 0.0
    for x in 0..<8 {
        for y in 0..<8 {
            guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
            let w = c.saturationComponent + 0.05
            r += c.redComponent * w; g += c.greenComponent * w; b += c.blueComponent * w; total += w
        }
    }
    guard total > 0 else { return .white }
    let avg = NSColor(deviceRed: r / total, green: g / total, blue: b / total, alpha: 1)
    return NSColor(hue: avg.hueComponent, saturation: min(1, avg.saturationComponent * 1.3),
                   brightness: max(0.85, avg.brightnessComponent), alpha: 1)
}
