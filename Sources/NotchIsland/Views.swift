import AppKit
import QuickLookThumbnailing

// MARK: - Small views

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Equaliser bars that bounce while playing.
final class BarsView: NSView {
    private var bars: [CALayer] = []
    var color = NSColor.white { didSet { bars.forEach { $0.backgroundColor = color.cgColor } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let w: CGFloat = 2.5, n = 4, gap = (frame.width - CGFloat(n) * w) / CGFloat(n - 1)
        for i in 0..<n {
            let b = CALayer()
            b.frame = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: frame.height)
            b.cornerRadius = w / 2
            b.backgroundColor = color.cgColor
            layer!.addSublayer(b)
            bars.append(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func setPlaying(_ on: Bool) {
        for (i, b) in bars.enumerated() {
            b.removeAnimation(forKey: "eq")
            b.transform = CATransform3DMakeScale(1, on ? 0.6 : 0.25, 1)
            guard on, !reduceMotion else { continue }
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.25; a.toValue = 1
            a.duration = [0.42, 0.55, 0.36, 0.48][i % 4]
            a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.beginTime = CACurrentMediaTime() - Double(i) * 0.13
            b.add(a, forKey: "eq")
        }
    }
}

final class BatteryView: NSView {
    private let fill = CALayer()
    private let inner: CGRect

    override init(frame: NSRect) {
        let body = CGRect(x: 0.5, y: 0.5, width: frame.width - 3.5, height: frame.height - 1)
        inner = body.insetBy(dx: 2, dy: 2)
        super.init(frame: frame)
        wantsLayer = true
        let outline = CAShapeLayer()
        outline.path = CGPath(roundedRect: body, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
        outline.fillColor = nil; outline.strokeColor = white(0.4).cgColor; outline.lineWidth = 1
        let cap = CALayer()
        cap.frame = CGRect(x: frame.width - 2, y: frame.height / 2 - 2, width: 2, height: 4)
        cap.backgroundColor = white(0.4).cgColor; cap.cornerRadius = 1
        fill.backgroundColor = NSColor.systemGreen.cgColor; fill.cornerRadius = 1.5
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.frame = CGRect(x: inner.minX, y: inner.minY, width: 0, height: inner.height)
        [outline, cap, fill].forEach { layer!.addSublayer($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func charge(to level: CGFloat) {
        animate(fill, "bounds", to: NSValue(rect: CGRect(x: 0, y: 0, width: inner.width * level, height: inner.height)))
    }
}

final class ProgressBar: NSView {
    var fraction: CGFloat = 0 { didSet { layoutBars() } }
    var onSeek: (CGFloat) -> Void = { _ in }
    private let track = CALayer(), fill = CALayer()
    private var hovered = false { didSet { layoutBars() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        track.backgroundColor = white(0.16).cgColor
        fill.backgroundColor = white(0.9).cgColor
        layer!.addSublayer(track); layer!.addSublayer(fill)
        layoutBars()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityElement(true); setAccessibilityRole(.slider); setAccessibilityLabel("Playback position")
    }
    required init?(coder: NSCoder) { fatalError() }

    private func layoutBars() {
        let h: CGFloat = hovered ? 6 : 4
        let r = CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
        track.frame = r; track.cornerRadius = h / 2
        fill.frame = CGRect(x: 0, y: r.minY, width: r.width * fraction, height: h); fill.cornerRadius = h / 2
    }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited(with e: NSEvent) { hovered = false }
    override func mouseDown(with e: NSEvent) { seek(e) }
    override func mouseDragged(with e: NSEvent) { seek(e) }
    private func seek(_ e: NSEvent) {
        fraction = min(max(convert(e.locationInWindow, from: nil).x / bounds.width, 0), 1)
        onSeek(fraction)
    }
}

final class IconButton: NSView {
    let image = NSImageView()
    private let point: CGFloat
    private let action: () -> Void

    init(_ symbol: String, size: CGFloat, point: CGFloat, label text: String, action: @escaping () -> Void) {
        self.point = point; self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true; layer!.cornerRadius = size / 2
        image.frame = bounds; image.image = sym(symbol, point); image.contentTintColor = .white
        addSubview(image)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ name: String, label text: String) {
        image.setSymbolImage(sym(name, point), contentTransition: .replace)
        setAccessibilityLabel(text)
    }
    override func hitTest(_ p: NSPoint) -> NSView? { !isHidden && frame.contains(p) ? self : nil }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { layer!.backgroundColor = white(0.12).cgColor }
    override func mouseExited(with e: NSEvent) { layer!.backgroundColor = nil }
    override func mouseDown(with e: NSEvent) { alphaValue = 0.5 }
    override func mouseUp(with e: NSEvent) {
        alphaValue = 1
        if bounds.contains(convert(e.locationInWindow, from: nil)) { action() }
    }
    override func accessibilityPerformPress() -> Bool { action(); return true }
}

/// A small coloured pill with a symbol and a word, like "Join".
final class PillButton: NSView {
    var action: () -> Void = {}

    init(_ title: String, symbol: String, color: NSColor, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 20))
        wantsLayer = true; layer!.cornerRadius = 10; layer!.backgroundColor = color.cgColor
        let icon = NSImageView(image: sym(symbol, 9))
        icon.contentTintColor = .white
        icon.frame = NSRect(x: 8, y: 4, width: 13, height: 12)
        let text = label(title, 11, .semibold)
        put(text, 23, 10, width - 29)
        addSubview(icon); addSubview(text)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ p: NSPoint) -> NSView? { !isHidden && frame.contains(p) ? self : nil }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { alphaValue = 0.85 }
    override func mouseExited(with e: NSEvent) { alphaValue = 1 }
    override func mouseDown(with e: NSEvent) { alphaValue = 0.6 }
    override func mouseUp(with e: NSEvent) {
        alphaValue = 1
        if bounds.contains(convert(e.locationInWindow, from: nil)) { action() }
    }
    override func accessibilityPerformPress() -> Bool { action(); return true }
}

/// Anything you can drag files out of. Finder decides move vs copy (same disk = move, ⌥ = copy).
class DragOutView: NSView, NSDraggingSource {
    var files: [URL] = []
    var onGone: ([URL]) -> Void = { _ in }
    private var downAt: NSPoint?

    override func hitTest(_ p: NSPoint) -> NSView? {
        let v = super.hitTest(p)
        return v is IconButton ? v : (v == nil ? nil : self)
    }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { downAt = convert(e.locationInWindow, from: nil) }
    override func mouseDragged(with e: NSEvent) {
        guard let p = downAt, !files.isEmpty else { return }
        downAt = nil
        let items = files.enumerated().map { (i, url) -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let o = CGFloat(min(i, 4)) * 4
            item.setDraggingFrame(NSRect(x: p.x - 24 + o, y: p.y - 24 - o, width: 48, height: 48),
                                  contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        beginDraggingSession(with: items, event: e, source: self)
    }
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation {
        c == .outsideApplication ? [.copy, .move, .generic] : []
    }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
        let sent = files
        // Finder can finish a move a beat after the drop, so look a moment later
        after(0.4) {
            let gone = sent.filter { !FileManager.default.fileExists(atPath: $0.path) }
            if !gone.isEmpty { self.onGone(gone) }
        }
    }
}

final class FileItemView: DragOutView {
    override var isFlipped: Bool { true }
    private let remove: IconButton

    init(url: URL, onRemove: @escaping () -> Void) {
        remove = IconButton("xmark.circle.fill", size: 18, point: 13, label: "Remove \(url.lastPathComponent)", action: onRemove)
        super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 62))
        files = [url]
        wantsLayer = true; layer!.cornerRadius = 10
        let icon = NSImageView(frame: NSRect(x: 16, y: 3, width: 40, height: 40))
        icon.image = NSWorkspace.shared.icon(forFile: url.path)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 40, height: 40), scale: 2, representationTypes: .thumbnail)
        Task { @MainActor in
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { icon.image = rep.nsImage }
        }
        let name = label(FileManager.default.displayName(atPath: url.path), 10, .medium, white(0.8))
        name.lineBreakMode = .byTruncatingMiddle
        put(name, 2, 52, 68, align: .center)
        remove.frame.origin = NSPoint(x: 55, y: -1)
        remove.isHidden = true
        remove.image.contentTintColor = white(0.9)
        ([icon, name, remove] as [NSView]).forEach(addSubview)
        toolTip = url.lastPathComponent
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(url.lastPathComponent)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with e: NSEvent) { layer!.backgroundColor = white(0.08).cgColor; remove.isHidden = false }
    override func mouseExited(with e: NSEvent) { layer!.backgroundColor = nil; remove.isHidden = true }
    override func mouseUp(with e: NSEvent) {
        if e.clickCount == 2, let url = files.first { NSWorkspace.shared.open(url) }
    }
}

final class DropZoneView: NSView {
    private let border = CAShapeLayer()
    private let icon = NSImageView(image: sym("tray.and.arrow.down", 20, .medium))
    private let text = label("Drop files here", 12, .medium)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer!.cornerRadius = 14
        border.path = CGPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 14, cornerHeight: 14, transform: nil)
        border.fillColor = nil; border.lineWidth = 1.5
        layer!.addSublayer(border)
        addSubview(icon); addSubview(text)
        setActive(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setActive(_ on: Bool) {
        let accent = NSColor.controlAccentColor
        border.strokeColor = (on ? accent : white(0.18)).cgColor
        border.lineDashPattern = on ? nil : [5, 4]
        layer!.backgroundColor = (on ? NSColor.black.blended(withFraction: 0.16, of: accent)! : .black).cgColor
        icon.contentTintColor = on ? accent : white(0.4)
        text.textColor = on ? accent : white(0.4)
        text.stringValue = on ? "Release to hold" : "Drop files here"
        // icon + text centred as one line
        let tw = ceil(text.fittingSize.width), x = ((bounds.width - 30 - tw) / 2).rounded()
        icon.frame = NSRect(x: x, y: bounds.midY - 13, width: 24, height: 26)
        put(text, x + 30, bounds.midY, tw)
        if on && !reduceMotion { icon.addSymbolEffect(.bounce) }
    }
}

// MARK: - Window

final class RootView: NSView {
    var onDrag: (Bool) -> Void = { _ in }
    var onDrop: ([URL]) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        if s.draggingSource is DragOutView { return [] }
        onDrag(true)
        return .copy
    }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { s.draggingSource is DragOutView ? [] : .copy }
    override func draggingExited(_ s: NSDraggingInfo?) { onDrag(false) }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrag(false)
        onDrop(urls)
        return !urls.isEmpty
    }
}

final class IslandPanel: NSPanel {
    init(_ frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)  // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false; isMovable = false; ignoresMouseEvents = true
        setFrame(frame, display: false)
    }
    override func constrainFrameRect(_ r: NSRect, to s: NSScreen?) -> NSRect { r }  // allow sitting over the menu bar
    override var canBecomeKey: Bool { false }
}
