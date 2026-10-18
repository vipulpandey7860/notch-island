import AppKit

// MARK: - Helpers

let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

func white(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }

func sym(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSImage {
    let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    return img.withSymbolConfiguration(.init(pointSize: size, weight: weight)) ?? img
}

func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .white, mono: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    return l
}

/// Frames a one-line label vertically centred on `cy`.
func put(_ l: NSTextField, _ x: CGFloat, _ cy: CGFloat, _ w: CGFloat, align: NSTextAlignment = .left) {
    let h = l.fittingSize.height
    l.frame = NSRect(x: x, y: (cy - h / 2).rounded(), width: w, height: h)
    l.alignment = align
}

func artView(_ img: NSImage?, _ f: NSRect, radius: CGFloat) -> NSImageView {
    let v = NSImageView(frame: f)
    v.image = img; v.imageScaling = .scaleProportionallyUpOrDown
    v.wantsLayer = true; v.layer!.cornerRadius = radius; v.layer!.masksToBounds = true
    return v
}

func pill(_ text: String, _ f: NSRect) -> NSView {
    let v = NSView(frame: f)
    v.wantsLayer = true; v.layer!.cornerRadius = f.height / 2
    v.layer!.backgroundColor = NSColor.controlAccentColor.cgColor
    let l = label(text, 10, .bold)
    put(l, 0, f.height / 2, f.width, align: .center)
    v.addSubview(l)
    return v
}

func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

/// Runs `f` on the main actor after `s` seconds; cancel the task to skip it.
@discardableResult
func after(_ s: Double, _ f: @escaping @MainActor () -> Void) -> Task<Void, Never> {
    Task { @MainActor in
        guard (try? await Task.sleep(for: .seconds(s))) != nil else { return }
        f()
    }
}

func fade(_ v: NSView, to a: CGFloat, delay: Double = 0, duration: Double = 0.2) {
    after(delay) { NSAnimationContext.runAnimationGroup { $0.duration = duration; v.animator().alphaValue = a } }
}

/// Spring (or a plain ease when Reduce Motion is on) from wherever the layer is right now.
/// `bounce: 0` settles without overshoot, so a shrinking island never dips inside the hardware notch.
func animate(_ layer: CALayer, _ key: String, to value: Any, bounce: CGFloat = 0.22, spring: Bool = true) {
    let a: CABasicAnimation
    if spring && !reduceMotion {
        let s = CASpringAnimation(perceptualDuration: 0.5, bounce: bounce)
        s.duration = s.settlingDuration
        a = s
    } else {
        a = CABasicAnimation()
        a.duration = 0.25
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    }
    a.keyPath = key
    a.fromValue = (layer.presentation() ?? layer).value(forKeyPath: key)
    a.toValue = value
    CATransaction.begin(); CATransaction.setDisableActions(true)
    layer.setValue(value, forKeyPath: key)
    CATransaction.commit()
    layer.add(a, forKey: key)
}

/// The island: flares out of the screen's top edge, straight sides, rounded bottom.
/// Every size uses the same segments so Core Animation can morph between them.
func islandPath(_ r: CGRect, radius: CGFloat, flare f: CGFloat) -> CGPath {
    let k: CGFloat = 0.5523, top = r.maxY, b = r.minY, x0 = r.minX, x1 = r.maxX
    let br = min(radius, r.height / 2, r.width / 2)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x0 - f, y: top))
    p.addCurve(to: CGPoint(x: x0, y: top - f), control1: CGPoint(x: x0 - f + k * f, y: top), control2: CGPoint(x: x0, y: top - f + k * f))
    p.addLine(to: CGPoint(x: x0, y: b + br))
    p.addCurve(to: CGPoint(x: x0 + br, y: b), control1: CGPoint(x: x0, y: b + br - k * br), control2: CGPoint(x: x0 + br - k * br, y: b))
    p.addLine(to: CGPoint(x: x1 - br, y: b))
    p.addCurve(to: CGPoint(x: x1, y: b + br), control1: CGPoint(x: x1 - br + k * br, y: b), control2: CGPoint(x: x1, y: b + br - k * br))
    p.addLine(to: CGPoint(x: x1, y: top - f))
    p.addCurve(to: CGPoint(x: x1 + f, y: top), control1: CGPoint(x: x1, y: top - f + k * f), control2: CGPoint(x: x1 + f - k * f, y: top))
    p.closeSubpath()
    return p
}

func eachBars(_ v: NSView, _ f: (BarsView) -> Void) {
    if let b = v as? BarsView { f(b) }
    v.subviews.forEach { eachBars($0, f) }
}
