// The tiny pixel robot. `Robot` is how it looks and moves (frames, walking, dancing, Z's), `Mascot` is the
// one living around the notch, and `RiderView` is the one riding the open island's progress bar.
import AppKit

// MARK: - Sprites: 12-pixel-wide frames, each pixel drawn 1.5pt (3 Retina pixels)

private let palette: [Character: NSColor] = [
    "K": NSColor(srgbRed: 0.11, green: 0.12, blue: 0.15, alpha: 1),  // outline
    "W": NSColor(srgbRed: 0.93, green: 0.95, blue: 0.97, alpha: 1),  // body
    "G": NSColor(srgbRed: 0.71, green: 0.74, blue: 0.80, alpha: 1),  // shading
    "D": NSColor(srgbRed: 0.14, green: 0.16, blue: 0.20, alpha: 1),  // face screen
    "E": NSColor(srgbRed: 0.42, green: 0.89, blue: 1.00, alpha: 1),  // eyes
    "C": NSColor(srgbRed: 0.23, green: 0.56, blue: 0.65, alpha: 1),  // closed eyes
    "R": NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1),  // Santa hat
    "O": NSColor(srgbRed: 0.96, green: 0.60, blue: 0.14, alpha: 1),  // pumpkin
]  // "A" is the antenna light, coloured at draw time

// What it wears on top (3 rows): its antenna, or a seasonal hat whose tip glows like the antenna
private let antennaTop = ["............", ".....AA.....", ".....KK....."]
private let pumpkinTop = [".....KA.....", "...OOOOOO...", "..OOOOOOOO.."]
private let santaTop = ["......RRRA..", "...RRRRRR...", ".WWWWWWWWWW."]

private func headwear() -> (name: String, rows: [String]) {
    switch Calendar.current.component(.month, from: Date()) {
    case 10: return ("pumpkin", pumpkinTop)
    case 12: return ("santa", santaTop)
    default: return ("antenna", antennaTop)
    }
}

private let head = [".KKKKKKKKKK.", ".KWWWWWWWWK.", ".KWDDDDDDWK."]
private let eyesAhead = [".KWDEDDEDWK.", ".KWDEDDEDWK."]
private let eyesRight = [".KWDDEDDEWK.", ".KWDDEDDEWK."]
private let eyesLeft = [".KWEDDEDDWK.", ".KWEDDEDDWK."]
private let eyesDown = [".KWDDDDDDWK.", ".KWDEDDEDWK."]
private let eyesShut = [".KWDDDDDDWK.", ".KWDCDDCDWK."]
private let torso = [
    ".KWWWWWWWWK.",
    ".KKKKKKKKKK.",
    "...KGWWGK...",
    "..KKGWWGKK..",
    "...KKKKKK...",
]
// Dancing: one arm pumps a pixel higher than the other
private let torsoArmL = [".KWWWWWWWWK.", ".KKKKKKKKKK.", "..KKGWWGK...", "...KGWWGKK..", "...KKKKKK..."]
private let torsoArmR = [".KWWWWWWWWK.", ".KKKKKKKKKK.", "...KGWWGKK..", "..KKGWWGK...", "...KKKKKK..."]
// Waving: its right arm up beside its head
private let torsoWave = [".KWWWWWWWWKK", ".KKKKKKKKKKK", "...KGWWGK.K.", "..KKGWWGK...", "...KKKKKK..."]
// Working: standing behind a little desk, hands on it
private func desk(_ hands: String) -> [String] {
    [".KWWWWWWWWK.", ".KKKKKKKKKK.", hands, "KKKKKKKKKKKK", "KGGGGGGGGGGK", ".K........K.", ".K........K."]
}
private let legsStand = ["....K..K....", "............"]
private let legsDangle = ["...K....K...", "...K....K..."]  // sitting on an edge

private let sprites: [Robot.Frame: [String]] = [
    .stand: head + eyesAhead + torso + legsStand,
    .look: head + eyesRight + torso + legsStand,
    .walk1: head + eyesRight + torso + ["...K...K....", "............"],
    .walk2: head + eyesRight + torso + ["....K...K...", "............"],
    .blink: head + eyesShut + torso + legsStand,
    .sit: head + eyesAhead + torso + legsDangle,
    .sleep: head + eyesShut + torso + legsDangle,
    .danceA: head + eyesLeft + torsoArmL + ["...K...K....", "............"],
    .danceB: head + eyesRight + torsoArmR + ["....K...K...", "............"],
    .wave1: head + [".KWDEDDEDWKK", ".KWDEDDEDWKK"] + torsoWave + legsStand,  // hand high
    .wave2: head + eyesAhead + torsoWave + legsStand,                         // hand lower
    .work1: head + eyesDown + desk("..KK....KK.."),
    .work2: head + eyesDown + desk("...KK..KK..."),
    .stretch: ["K.KKKKKKKK.K", "KKWWWWWWWWKK", ".KWDDDDDDWK."] + eyesShut + [  // arms up, eyes shut: a yawn
        ".KWWWWWWWWK.",
        ".KKKKKKKKKK.",
        "...KGWWGK...",
        "...KGWWGK...",
        "...KKKKKK...",
    ] + legsStand,
]
private let zzz = ["EEEE", "..E.", ".E..", "EEEE"]

private func pixels(_ rows: [String], antenna: NSColor) -> CGImage {
    let w = rows[0].count, h = rows.count
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (r, row) in rows.enumerated() {
        for (c, ch) in row.enumerated() {
            guard let color = ch == "A" ? antenna : palette[ch] else { continue }
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: c, y: h - 1 - r, width: 1, height: 1))
        }
    }
    return ctx.makeImage()!
}

// MARK: - Robot

/// A posable pixel robot. Its layer's origin is at its boots: put that on a surface, and rotate the
/// layer to stand it on walls and ceilings.
final class Robot {
    enum Frame: String {
        case stand, look, walk1, walk2, blink, sit, sleep, stretch, danceA, danceB, wave1, wave2, work1, work2
    }
    static let px: CGFloat = 1.5
    static let half: CGFloat = 9  // half its width
    static let restingAntenna = NSColor(srgbRed: 1, green: 0.42, blue: 0.5, alpha: 1)

    let layer = CALayer()
    private let body = CALayer()    // flips to face left or right
    private let sprite = CALayer()
    private(set) var current = Frame.stand
    private(set) var facing: CGFloat = 1
    private var antenna = Robot.restingAntenna
    private var cycle: (frames: [Frame], period: Double)?  // frames looping right now (walking, dancing)
    private var cache: [String: CGImage] = [:]
    /// Bobs along to music while standing or sitting.
    var bobbing = false { didSet { if bobbing != oldValue { updateBob() } } }

    init() {
        layer.bounds = .zero
        layer.actions = ["position": NSNull(), "transform": NSNull()]
        sprite.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        sprite.magnificationFilter = .nearest
        layer.addSublayer(body)
        body.addSublayer(sprite)
    }

    func show(_ f: Frame) {
        cycle = nil
        sprite.removeAnimation(forKey: "frames")
        draw(f)
    }

    /// Loops through `frames`, once round every `period` seconds.
    func loop(_ frames: [Frame], period: Double) {
        cycle = (frames, period)
        draw(frames[0])
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = frames.map { image($0) }
        a.calculationMode = .discrete
        a.duration = period; a.repeatCount = .infinity
        sprite.add(a, forKey: "frames")
    }

    func walk(period: Double = 0.32) { loop([.walk1, .walk2], period: period) }

    /// Steps foot to foot with its eyes darting, swaying and bouncing at ~115 bpm.
    func dance(_ on: Bool) {
        sprite.removeAnimation(forKey: "sway")
        sprite.removeAnimation(forKey: "bounce")
        guard on else { show(.stand); return }
        guard !reduceMotion else { show(.danceA); return }
        let beat = 0.52
        loop([.danceA, .danceB], period: 2 * beat)
        let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        sway.values = [0, 0.14, 0, -0.14, 0]
        sway.duration = 2 * beat; sway.repeatCount = .infinity; sway.isAdditive = true
        sprite.add(sway, forKey: "sway")
        let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounce.values = [0, 2.5 * Self.px, 0]
        bounce.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        bounce.duration = beat; bounce.repeatCount = .infinity; bounce.isAdditive = true
        sprite.add(bounce, forKey: "bounce")
    }

    func hop() {
        let a = CAKeyframeAnimation(keyPath: "transform.translation.y")
        a.values = [0, 7, 0]; a.keyTimes = [0, 0.45, 1]
        a.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        a.duration = 0.36; a.isAdditive = true
        sprite.add(a, forKey: "hop")
    }

    func face(_ f: CGFloat) {
        guard f != facing else { return }
        facing = f
        body.transform = CATransform3DMakeScale(f, 1, 1)  // implicit animation: a quick squash-turn
    }

    func setAntenna(_ c: NSColor) {
        guard c != antenna else { return }
        antenna = c
        if let c = cycle { loop(c.frames, period: c.period) } else { draw(current) }
    }

    func puffZ() {
        let z = CALayer()
        z.contents = image("z", zzz, top: [])
        z.magnificationFilter = .nearest
        z.frame = CGRect(x: 3, y: 19, width: 4 * Self.px, height: 4 * Self.px)
        layer.addSublayer(z)
        let rise = CABasicAnimation(keyPath: "position.y"); rise.byValue = 12
        let fadeOut = CABasicAnimation(keyPath: "opacity"); fadeOut.fromValue = 1; fadeOut.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [rise, fadeOut]; g.duration = 1.8
        g.fillMode = .forwards; g.isRemovedOnCompletion = false
        z.add(g, forKey: nil)
        after(1.8) { z.removeFromSuperlayer() }
    }

    /// Drops looping and one-off animations, holding the current pose.
    func stop() {
        cycle = nil
        for key in ["frames", "hop", "sway", "bounce"] { sprite.removeAnimation(forKey: key) }
        updateBob()
    }

    private func draw(_ f: Frame) {
        current = f
        let img = image(f)
        sprite.contents = img
        // Pixel rows under the surface it stands on: legs dangle when sitting; the desk stands on it
        let below: CGFloat = [.sit, .sleep].contains(f) ? 2 : [.work1, .work2].contains(f) ? 0 : 1
        sprite.frame = CGRect(x: -Self.half, y: -below * Self.px,
                              width: CGFloat(img.width) * Self.px, height: CGFloat(img.height) * Self.px)
        updateBob()
    }

    private func updateBob() {
        let on = bobbing && !reduceMotion && cycle == nil && [.stand, .look, .sit].contains(current)
        if on, sprite.animation(forKey: "bob") == nil {
            let a = CABasicAnimation(keyPath: "transform.translation.y")
            a.fromValue = 0; a.toValue = Self.px
            a.duration = 0.26; a.autoreverses = true; a.repeatCount = .infinity
            a.isAdditive = true
            sprite.add(a, forKey: "bob")
        } else if !on {
            sprite.removeAnimation(forKey: "bob")
        }
    }

    private func image(_ f: Frame) -> CGImage {
        let hat = headwear()
        return image(f.rawValue + hat.name, sprites[f]!, top: hat.rows)
    }
    private func image(_ key: String, _ rows: [String], top: [String]) -> CGImage {
        let k = key + antenna.description
        if let img = cache[k] { return img }
        let img = pixels(top + rows, antenna: antenna)
        cache[k] = img
        return img
    }
}

// MARK: - Mascot: the robot living around the notch

/// On magnet boots it walks the menu bar, climbs the notch's walls and hangs underneath; it sits,
/// dozes, dances to music, works at a desk during focus time, and reacts to what Notch Island is doing.
final class Mascot {
    typealias Frame = Robot.Frame
    /// Nothing going on: it sleeps. Files or downloads: it potters about. Music: it parties and never
    /// sleeps. Focus timer: it works.
    enum Mood { case asleep, calm, party, work }
    /// Where its boots are: the menu bar's bottom edge either side, the island's side walls, or its underside.
    enum Surface { case floorL, wallL, ceiling, wallR, floorR }
    struct Spot { var surface: Surface; var pos: CGFloat }  // pos: x on floors/ceiling, y on walls

    private let half = Robot.half
    private let reach: CGFloat = 64     // how far it strays along the menu bar
    private var speed: CGFloat { tired ? 8 : 16 }  // points per second

    let robot = Robot()
    var container: CALayer { robot.layer }
    var world = CGRect.zero             // the resting island (or bare notch) it lives around, window coords
    var topY: CGFloat = 0               // the screen's top edge
    var mouse: () -> CGPoint = { .zero }
    var frozen = false                  // snapshot mode: only `place` moves it
    /// Low battery: slower, sits more, red antenna.
    var tired = false { didSet { if tired != oldValue { robot.setAntenna(antennaColor) } } }
    private(set) var here = Spot(surface: .floorL, pos: 0)
    private var rot: CGFloat = 0
    private var mood = Mood.calm, watching = false
    private var musicAccent = Robot.restingAntenna
    private var lastWave = Date.distantPast
    private var yawnedOn: Int?          // the day it last did its morning yawn
    private var task: Task<Void, Never>?

    private var antennaColor: NSColor { mood == .party ? musicAccent : tired ? .systemRed : Robot.restingAntenna }
    private var isNight: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 22 || h < 6
    }

    // MARK: Events from the island

    func start() {
        place(Spot(surface: .floorL, pos: range(.floorL).upperBound - 12), .sleep)
        run {}
    }

    /// Snapshot mode: stop living; only `place` moves it from now on.
    func freeze() {
        frozen = true
        task?.cancel()
        settle()
    }

    func setVisible(_ on: Bool) {
        container.isHidden = !on
        if on { start() } else { task?.cancel(); settle() }
    }

    /// The island opened: the rider on the progress bar takes over until it closes.
    func pause() {
        task?.cancel()
        settle()
        container.opacity = 0
    }

    func resume() {
        container.opacity = 1
        run {}
    }

    /// The resting island changed size (music started or stopped, files held): step to the new edge.
    func setWorld(_ r: CGRect) {
        guard r != world else { return }
        world = r
        run { [unowned self] in try await self.relocate() }
    }

    /// `accent` colours its antenna while music plays.
    func setMood(_ m: Mood, accent color: NSColor) {
        musicAccent = color
        let old = mood
        mood = m
        robot.setAntenna(antennaColor)
        guard m != old else { return }
        robot.bobbing = m == .party
        switch m {
        case .asleep, .work: run {}                                       // live() takes it from here
        case .party: run { [unowned self] in try await self.hop() }       // a song! hop up
        case .calm:                                                       // waking up, or a focus break: stretch
            run { [unowned self] in if old == .asleep || old == .work { try await self.yawn() } }
        }
    }

    func pluggedIn() {
        run { [unowned self] in
            self.robot.setAntenna(.systemGreen)
            defer { self.robot.setAntenna(self.antennaColor) }
            try await self.hop(times: 2)
            try await self.nap(0.6)
        }
    }

    /// A download finished and landed on the shelf.
    func cheer() { run { [unowned self] in try await self.hop(times: 2) } }

    func meetingSoon() { run { [unowned self] in try await self.yawn() } }

    func setWatching(_ on: Bool) {
        guard on != watching else { return }
        watching = on
        if on { run { [unowned self] in try await self.watch() } }
    }

    /// The cursor moved (window coords): if it comes close, wave. At most every few seconds.
    func cursor(at p: CGPoint) {
        guard !frozen, !container.isHidden, container.opacity > 0, !watching,
              Date().timeIntervalSince(lastWave) > 8,
              hypot(p.x - container.position.x, p.y - container.position.y) < 30 else { return }
        lastWave = Date()
        run { [unowned self] in try await self.wave(toward: p) }
    }

    // MARK: Geometry

    func range(_ s: Surface) -> ClosedRange<CGFloat> {
        let line = world.minY
        switch s {
        case .floorL: return (world.minX - reach)...(world.minX - half)
        case .floorR: return (world.maxX + half)...(world.maxX + reach)
        case .ceiling: return (world.minX + half + 6)...(world.maxX - half - 6)  // clear of the rounded corners
        case .wallL, .wallR: return (line + half)...max(line + half, topY - half)
        }
    }

    private func point(_ s: Spot) -> CGPoint {
        switch s.surface {
        case .floorL, .floorR, .ceiling: return CGPoint(x: s.pos, y: world.minY)
        case .wallL: return CGPoint(x: world.minX, y: s.pos)
        case .wallR: return CGPoint(x: world.maxX, y: s.pos)
        }
    }

    /// Rotation that puts its boots on the surface (body pointing away from it).
    private func angle(_ s: Surface) -> CGFloat {
        switch s {
        case .floorL, .floorR: return 0
        case .wallL: return .pi / 2
        case .ceiling: return .pi
        case .wallR: return -.pi / 2
        }
    }

    /// Which way "forward" (its own +x) runs along the surface's pos axis.
    private func forward(_ s: Surface) -> CGFloat { s == .ceiling || s == .wallR ? -1 : 1 }

    private enum Corner { case left, right }
    private func corners(_ s: Surface) -> [Corner] {
        switch s {
        case .floorL, .wallL: return [.left]
        case .ceiling: return [.left, .right]
        case .wallR, .floorR: return [.right]
        }
    }
    /// The end of surface `s` at the given corner.
    private func end(_ s: Surface, _ c: Corner) -> Spot {
        let r = range(s)
        switch (s, c) {
        case (.floorL, _), (.ceiling, .right): return Spot(surface: s, pos: r.upperBound)
        default: return Spot(surface: s, pos: r.lowerBound)
        }
    }

    /// Waypoints from here to `dest`, through the corners where surfaces meet.
    private func route(to dest: Spot) -> [Spot] {
        let a = here.surface, b = dest.surface
        if a == b { return [dest] }
        if let c = corners(a).first(where: corners(b).contains) { return [end(a, c), end(b, c), dest] }
        let (ca, cb): (Corner, Corner) = corners(a) == [.left] ? (.left, .right) : (.right, .left)
        return [end(a, ca), end(.ceiling, ca), end(.ceiling, cb), end(b, cb), dest]
    }

    // MARK: Moving

    /// Puts it somewhere instantly (start-up and snapshots).
    func place(_ s: Spot, _ f: Frame, facing: CGFloat = 1) {
        settle()
        here = s
        rot = angle(s.surface)
        container.transform = CATransform3DMakeRotation(rot, 0, 0, 1)
        container.position = point(s)
        robot.face(facing)
        robot.show(f)
    }

    private func move(to p: CGPoint, duration: Double, linear: Bool, turnTo newRot: CGFloat? = nil) {
        let a = CABasicAnimation(keyPath: "position")
        a.fromValue = NSValue(point: (container.presentation() ?? container).position)
        a.toValue = NSValue(point: p)
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: linear ? .linear : .easeInEaseOut)
        container.position = p
        container.add(a, forKey: "move")
        guard let r = newRot else { return }
        let t = CABasicAnimation(keyPath: "transform.rotation.z")
        t.fromValue = rot; t.toValue = r; t.duration = duration
        t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rot = r
        container.transform = CATransform3DMakeRotation(r, 0, 0, 1)
        container.add(t, forKey: "turn")
    }

    /// Stops wherever it is right now (mid-walk), or finishes a corner turn instantly.
    private func settle() {
        if let p = container.presentation(), container.animation(forKey: "move") != nil,
           container.animation(forKey: "turn") == nil {
            container.position = p.position
            here.pos = here.surface == .wallL || here.surface == .wallR ? p.position.y : p.position.x
        }
        container.removeAllAnimations()
        robot.stop()
    }

    private func nap(_ s: Double) async throws { try await Task.sleep(for: .seconds(s)) }

    @MainActor private func walk(to target: CGFloat) async throws {
        let d = abs(target - here.pos)
        guard d > 0.5 else { return }
        robot.face((target > here.pos ? 1 : -1) * forward(here.surface))
        robot.walk(period: tired ? 0.5 : 0.32)
        here.pos = target
        move(to: point(here), duration: d / speed, linear: true)
        try await nap(d / speed)
        robot.show(.look)
    }

    /// Swings its boots from one surface onto the next at a corner.
    @MainActor private func turn(onto s: Spot) async throws {
        robot.show(.stand)
        let delta = CGFloat(remainder(Double(angle(s.surface) - rot), 2 * .pi))  // the short way round
        here = s
        move(to: point(s), duration: 0.32, linear: false, turnTo: rot + delta)
        try await nap(0.34)
    }

    @MainActor private func go(to dest: Spot) async throws {
        for step in route(to: dest) {
            if step.surface == here.surface { try await walk(to: step.pos) } else { try await turn(onto: step) }
        }
    }

    @MainActor private func relocate() async throws {
        let r = range(here.surface)
        here.pos = min(max(here.pos, r.lowerBound), r.upperBound)
        robot.show(.stand)
        move(to: point(here), duration: 0.3, linear: false)
        try await nap(0.3)
    }

    // MARK: Behaviour

    /// Cancels whatever it's doing, runs `first`, then goes back to living its life.
    private func run(_ first: @escaping @MainActor () async throws -> Void) {
        guard !frozen, !container.isHidden else { return }
        task?.cancel()
        settle()
        task = Task { @MainActor [weak self] in
            do {
                try await first()
                try await self?.live()
            } catch {}  // cancelled: a newer reaction took over
        }
    }

    @MainActor private func live() async throws {
        while true {
            if mood != .asleep, morningYawnDue() { try await yawn() }
            let roll = Double.random(in: 0..<1)
            switch mood {
            case .asleep:
                try await bed()
            case .work:
                try await work()
            case .party:
                if roll < 0.40 {
                    if tired && Bool.random() { try await sit(.random(in: 4...8)) } else { try await dance(.random(in: 5...10)) }
                }
                else if roll < 0.62 { try await wander() }
                else if roll < 0.72 { try await climb() }
                else if roll < 0.82 { try await hang() }
                else if roll < 0.94 { try await sit(.random(in: 4...8)) }  // bobs along
                else { try await idle(.random(in: 2...4)) }
            case .calm:
                let sleepy = tired || isNight  // more sitting and dozing
                if roll < (sleepy ? 0.15 : 0.32) { try await wander() }
                else if roll < (sleepy ? 0.22 : 0.47) { try await climb() }
                else if roll < (sleepy ? 0.30 : 0.62) { try await hang() }
                else if roll < (sleepy ? 0.60 : 0.80) { try await sit(.random(in: 6...14)) }
                else if roll < 0.90 { try await doze(.random(in: 15...40)) }
                else { try await idle(.random(in: 3...7)) }
            }
        }
    }

    /// One yawn the first time it's up and about between 6 and 10 in the morning.
    private func morningYawnDue() -> Bool {
        let cal = Calendar.current, now = Date()
        let day = cal.ordinality(of: .day, in: .era, for: now)
        guard (6..<10).contains(cal.component(.hour, from: now)), yawnedOn != day else { return false }
        yawnedOn = day
        return true
    }

    @MainActor private func idle(_ seconds: Double) async throws {
        robot.show(.stand)
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try await nap(.random(in: 0.8...2.2))
            switch Int.random(in: 0..<3) {
            case 0:
                let was = robot.current
                robot.show(.blink); try await nap(0.14); robot.show(was)
            case 1:
                robot.face(-robot.facing); robot.show(.look)  // looks around
            default:
                robot.show(.stand)
            }
        }
    }

    @MainActor private func wander() async throws {
        let floor: Surface = Bool.random() ? .floorL : .floorR
        try await go(to: Spot(surface: floor, pos: .random(in: range(floor))))
        try await idle(.random(in: 1...3))
    }

    @MainActor private func climb() async throws {
        let left = Bool.random()
        let wall: Surface = left ? .wallL : .wallR
        try await go(to: Spot(surface: wall, pos: range(wall).upperBound))
        try await idle(.random(in: 2...4))
        let floor: Surface = left ? .floorL : .floorR
        try await go(to: Spot(surface: floor, pos: left ? range(floor).upperBound - 10 : range(floor).lowerBound + 10))
    }

    @MainActor private func hang() async throws {
        let r = range(.ceiling)
        try await go(to: Spot(surface: .ceiling, pos: .random(in: r)))
        try await idle(.random(in: 2...5))
        try await walk(to: .random(in: r))
        try await idle(.random(in: 1...3))
    }

    @MainActor private func toFloor() async throws {
        switch here.surface {
        case .floorL, .floorR: return
        case .wallL: try await go(to: Spot(surface: .floorL, pos: range(.floorL).upperBound - 10))
        case .wallR: try await go(to: Spot(surface: .floorR, pos: range(.floorR).lowerBound + 10))
        case .ceiling:
            let left = here.pos < world.midX
            try await go(to: left ? Spot(surface: .floorL, pos: range(.floorL).upperBound - 10)
                                  : Spot(surface: .floorR, pos: range(.floorR).lowerBound + 10))
        }
    }

    /// Goes to its spot right beside the notch, facing it.
    @MainActor private func toSpot() async throws {
        try await toFloor()
        let left = here.surface == .floorL
        try await walk(to: left ? range(.floorL).upperBound - 12 : range(.floorR).lowerBound + 12)
        robot.face(left ? 1 : -1)
    }

    /// Nothing going on: tuck in beside the notch and sleep until something happens.
    @MainActor private func bed() async throws {
        try await toSpot()
        try await doze(.greatestFiniteMagnitude)
    }

    /// Focus time: it types away at a tiny desk beside the notch, pausing now and then to think.
    @MainActor private func work() async throws {
        try await toSpot()
        while true {
            robot.loop([.work1, .work2], period: 0.42)
            try await nap(.random(in: 6...12))
            robot.show(.work1)
            try await nap(.random(in: 1...2.5))
        }
    }

    /// Sits on the menu bar's edge, legs dangling, blinking now and then.
    @MainActor private func sit(_ seconds: Double) async throws {
        try await toFloor()
        robot.show(.sit)
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try await nap(.random(in: 1.5...4))
            robot.show(.sleep); try await nap(0.14); robot.show(.sit)
        }
    }

    @MainActor private func doze(_ seconds: Double) async throws {
        try await toFloor()
        robot.show(.sleep)
        let end = Date().addingTimeInterval(min(seconds, 1e9))
        while Date() < end { robot.puffZ(); try await nap(1.4) }
        robot.show(.sit)
        try await nap(0.8)
    }

    @MainActor private func dance(_ seconds: Double) async throws {
        try await toFloor()
        robot.dance(true)
        try await nap(seconds)
        robot.dance(false)
    }

    @MainActor private func hop(times: Int = 1) async throws {
        for _ in 0..<times {
            robot.hop()
            try await nap(0.4)
        }
    }

    @MainActor private func yawn() async throws {
        try await toFloor()
        robot.show(.stretch)
        try await nap(1.6)
        robot.show(.stand)
        try await nap(0.4)
    }

    @MainActor private func wave(toward p: CGPoint) async throws {
        let dx = (p.x - container.position.x) * cos(rot) + (p.y - container.position.y) * sin(rot)
        robot.face(dx >= 0 ? 1 : -1)
        robot.loop([.wave1, .wave2], period: 0.36)
        try await nap(1.6)
        robot.show(.stand)
    }

    /// Turns to follow a file being dragged until the drag ends.
    @MainActor private func watch() async throws {
        robot.show(.look)
        while watching {
            let m = mouse(), p = container.position
            let dx = (m.x - p.x) * cos(rot) + (m.y - p.y) * sin(rot)  // cursor offset along its own x axis
            if abs(dx) > 4 { robot.face(dx > 0 ? 1 : -1) }
            try await nap(0.15)
        }
    }
}

// MARK: - Rider: the robot on the open island's progress bar

/// Walks along the progress bar as the song plays, sits down on it when paused, dances to live
/// streams (no progress to ride) and sleeps at the start of it when nothing plays.
final class RiderView: NSView {
    let robot = Robot()
    private let barX: CGFloat, barWidth: CGFloat, floorY: CGFloat
    private var doing = ""
    private var active = false
    private var zzz: Task<Void, Never>?

    /// `barX`, `barWidth` and `floorY` (the bar's top edge) are in this view's own coordinates.
    init(frame: NSRect, barX: CGFloat, barWidth: CGFloat, floorY: CGFloat) {
        self.barX = barX; self.barWidth = barWidth; self.floorY = floorY
        super.init(frame: frame)
        wantsLayer = true
        layer!.addSublayer(robot.layer)
        robot.layer.position = CGPoint(x: barX + 14, y: floorY)
        robot.show(.sleep)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ p: NSPoint) -> NSView? { nil }  // clicks reach the progress bar underneath

    /// Animates only while the island is open.
    func setActive(_ on: Bool) {
        active = on
        doing = ""
        if !on { zzz?.cancel(); robot.stop() }
    }

    /// Call on every track change and once a second while open.
    func update(_ t: Track?) {
        guard active else { return }
        let x: CGFloat, next: String
        if let t, t.duration > 0 {
            x = barX + barWidth * CGFloat(t.position / t.duration)
            next = t.playing ? "walk" : "sit"
        } else if let t, t.playing {
            x = barX + barWidth / 2
            next = "dance"
        } else {
            x = barX + 14
            next = "sleep"
        }
        robot.setAntenna(t?.playing == true ? t!.accent : Robot.restingAntenna)
        move(to: x)
        guard next != doing else { return }
        doing = next
        zzz?.cancel()
        robot.dance(false)
        robot.face(1)
        switch next {
        case "walk": robot.walk(period: 0.5)  // the bar creeps along, so do its steps
        case "sit": robot.show(.sit)
        case "dance": robot.dance(true)
        default:
            robot.show(.sleep)
            zzz = Task { @MainActor [weak self] in
                while !Task.isCancelled, let self, self.doing == "sleep" {
                    self.robot.puffZ()
                    try? await Task.sleep(for: .seconds(1.4))
                }
            }
        }
    }

    private func move(to x: CGFloat) {
        let from = (robot.layer.presentation() ?? robot.layer).position
        let to = CGPoint(x: x, y: floorY)
        guard abs(to.x - from.x) > 0.1 else { return }
        // Keeps pace with the once-a-second updates; a seek or a new track zips across instead
        let jump = abs(to.x - from.x) > 20
        let a = CABasicAnimation(keyPath: "position")
        a.fromValue = NSValue(point: from)
        a.toValue = NSValue(point: to)
        a.duration = jump ? 0.35 : 1
        a.timingFunction = CAMediaTimingFunction(name: jump ? .easeInEaseOut : .linear)
        robot.layer.position = to
        robot.layer.add(a, forKey: "move")
    }
}
