// The open island's planner cards (today's tasks and the day's note) and the due-task alert.
import AppKit

// MARK: - Shared bits

/// The open island's dark rounded cards.
func styleCard(_ v: NSView) {
    v.wantsLayer = true
    v.layer!.cornerRadius = 18
    v.layer!.backgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1).cgColor
    v.layer!.borderWidth = 1
    v.layer!.borderColor = white(0.06).cgColor
}

/// A dashed hairline across `width`, the cards' separator.
func dashedLine(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat) -> NSView {
    let v = NSView(frame: NSRect(x: x, y: y, width: width, height: 1))
    v.wantsLayer = true
    let l = CAShapeLayer(), p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0.5)); p.addLine(to: CGPoint(x: width, y: 0.5))
    l.path = p; l.strokeColor = white(0.1).cgColor; l.lineWidth = 1; l.lineDashPattern = [3, 3]
    v.layer!.addSublayer(l)
    return v
}

/// "Today", "Tomorrow", "Yesterday", a weekday within the week, else "Thu 12 Nov".
func dayName(_ offset: Int) -> String {
    let d = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
    switch offset {
    case 0: return "Today"
    case 1: return "Tomorrow"
    case -1: return "Yesterday"
    case 2...6: return d.formatted(.dateTime.weekday(.wide))
    default: return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// "Tomorrow, 5:00 PM", or just "Friday" for a task without a reminder.
func whenText(_ offset: Int, _ due: Date?) -> String {
    dayName(offset) + (due.map { ", " + $0.formatted(date: .omitted, time: .shortened) } ?? "")
}

/// "5:00 PM" today, otherwise "Fri 5:00 PM".
func dueText(_ d: Date) -> String {
    Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened)
        : d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

/// A borderless text field that takes the first click even while another app is in front.
final class InputField: NSTextField {
    var onFocus: () -> Void = {}
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus() }
        return ok
    }
}

func inputField(_ placeholder: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> InputField {
    let f = InputField()
    f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none
    f.font = .systemFont(ofSize: size, weight: weight); f.textColor = white(0.95)
    f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
        .foregroundColor: white(0.32), .font: NSFont.systemFont(ofSize: size, weight: weight)])
    f.usesSingleLineMode = true
    f.cell?.wraps = false; f.cell?.isScrollable = true
    return f
}

// MARK: - Today: one day's tasks, and the box you type new ones into

final class TodayCard: FlippedView, NSTextFieldDelegate {
    let field = inputField("Add a task…   try “call mom tomorrow 5pm”", 13)
    var onEscape: () -> Void = {}
    private unowned let planner: Planner
    private var offset = 0, showDone = false, showOffset = 0, listHeight: CGFloat = 0
    private let heading = label("Today", 14, .semibold)
    private let tabs = Tabs()
    private let date = label("", 11.5, .medium, white(0.5))
    private let calIcon = NSImageView(image: sym("calendar", 10, .medium))
    private var prev: IconButton!, next: IconButton!, back: IconButton!
    private let scroll = NSScrollView(), rows = FlippedView()
    private let emptyHost = NSView(), robot = Robot()
    private let emptyTitle = label("", 13, .semibold, white(0.85)), emptySub = label("", 11.5, .regular, white(0.45))
    // The line above the box: what's about to be saved, or where the last task went
    private let hintIcon = NSImageView(), hint = label("", 11.5, .medium, white(0.5)), hintKey = label("", 11, .medium, white(0.35))
    private let show = PillButton("Show", symbol: "arrow.right", color: white(0.14), width: 62)
    private var toastWork: Task<Void, Never>?
    private let box = NSView(), keyBox = NSView(), keycap = label("⌥N", 10.5, .medium, white(0.45))

    init(frame: NSRect, planner: Planner) {
        self.planner = planner
        super.init(frame: frame)
        styleCard(self)
        let w = frame.width, h = frame.height

        // Header: the day, To do | Done, then ‹ date › on the right
        put(heading, 14, 24, 120)
        tabs.frame.origin.y = 13
        tabs.onPick = { [unowned self] done in self.showDone = done; self.reload() }
        prev = IconButton("chevron.left", size: 22, point: 11, label: "Previous day") { [unowned self] in self.go(self.offset - 1) }
        next = IconButton("chevron.right", size: 22, point: 11, label: "Next day") { [unowned self] in self.go(self.offset + 1) }
        back = IconButton("arrow.uturn.backward", size: 22, point: 11, label: "Back to today") { [unowned self] in self.go(0) }
        next.frame.origin = NSPoint(x: w - 32, y: 13)
        [prev, next, back].forEach { $0!.image.contentTintColor = white(0.55) }
        calIcon.contentTintColor = white(0.45)

        // The list, or a robot when it's empty
        scroll.frame = NSRect(x: 14, y: 44, width: w - 28, height: 0)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay; scroll.scrollerKnobStyle = .light; scroll.autohidesScrollers = true
        rows.frame = NSRect(x: 0, y: 0, width: w - 28, height: 0)
        scroll.documentView = rows
        emptyHost.wantsLayer = true
        emptyHost.layer!.addSublayer(robot.layer)
        robot.layer.setAffineTransform(CGAffineTransform(scaleX: 1.3, y: 1.3))
        [emptyTitle, emptySub].forEach { emptyHost.addSubview($0) }

        // The box
        box.frame = NSRect(x: 14, y: h - 48, width: w - 28, height: 34)
        box.wantsLayer = true; box.layer!.cornerRadius = 10; box.layer!.borderWidth = 1
        let plus = NSImageView(image: sym("plus", 12, .semibold))
        plus.contentTintColor = white(0.45); plus.frame = NSRect(x: 9, y: 10, width: 14, height: 14)
        keyBox.frame = NSRect(x: box.frame.width - 40, y: 8, width: 30, height: 18)
        keyBox.wantsLayer = true; keyBox.layer!.cornerRadius = 5; keyBox.layer!.borderWidth = 1; keyBox.layer!.borderColor = white(0.14).cgColor
        put(keycap, 0, 9, 30, align: .center)
        keyBox.addSubview(keycap)
        let fh = field.fittingSize.height
        field.frame = NSRect(x: 29, y: ((34 - fh) / 2).rounded(), width: keyBox.frame.minX - 37, height: fh)
        field.delegate = self
        field.onFocus = { [unowned self] in self.styleBox(focused: true) }
        [plus, field, keyBox].forEach { box.addSubview($0) }
        styleBox(focused: false)
        hintIcon.frame = NSRect(x: 18, y: box.frame.minY - 21, width: 13, height: 13)
        put(hint, 36, box.frame.minY - 14, w - 36 - 120)
        put(hintKey, w - 134, box.frame.minY - 14, 120, align: .right)
        show.frame.origin = NSPoint(x: w - 14 - 62, y: box.frame.minY - 24)
        show.action = { [unowned self] in self.go(self.showOffset); self.setHint(nil) }

        ([heading, tabs, prev, next, back, calIcon, date, scroll, emptyHost, hintIcon, hint, hintKey, show, box] as [NSView]).forEach(addSubview)
        setHint(nil)
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func go(_ day: Int) {
        offset = day; showDone = false
        reload()
    }

    /// Rebuilds the list from the planner; leaves it alone while a task's being edited.
    func reload() {
        guard !rows.subviews.contains(where: { ($0 as? TaskRow)?.editing != nil }) else { return }
        let (todo, done) = planner.list(dayKey(in: offset)), items = showDone ? done : todo
        layoutHeader(todo: todo.count, done: done.count)
        rows.subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 0
        for t in items {
            let r = TaskRow(t, width: rows.frame.width, planner: planner)
            r.frame.origin.y = y
            y += r.frame.height
            rows.addSubview(r)
        }
        listHeight = y
        layoutList()
        showEmpty(items.isEmpty, allDone: !showDone && !done.isEmpty, finished: done.count)
    }

    private func layoutHeader(todo: Int, done: Int) {
        heading.stringValue = dayName(offset)
        heading.frame.size.width = ceil(heading.fittingSize.width)
        tabs.set(todo: todo, done: done, showingDone: showDone)
        tabs.frame.origin.x = heading.frame.maxX + 10
        // The heading names the day already; the date only needs adding for the days that go by name
        let named = (-1...6).contains(offset)
        date.isHidden = !named; calIcon.isHidden = !named
        date.stringValue = Calendar.current.date(byAdding: .day, value: offset, to: Date())!.formatted(.dateTime.day().month(.abbreviated))
        let dw = named ? ceil(date.fittingSize.width) : 0
        put(date, next.frame.minX - 2 - dw, 24, dw)
        calIcon.frame = NSRect(x: date.frame.minX - 16, y: 18, width: 12, height: 12)
        prev.frame.origin = NSPoint(x: (named ? calIcon.frame.minX - 2 : next.frame.minX - 4) - 22, y: 13)
        back.frame.origin = NSPoint(x: prev.frame.minX - 4 - 22, y: 13)
        back.isHidden = offset == 0
    }

    private func layoutList() {
        let bottom = box.frame.minY - (hint.isHidden ? 8 : 28)
        scroll.frame.size.height = bottom - scroll.frame.minY
        rows.frame.size.height = max(listHeight, scroll.frame.height)
        emptyHost.frame = scroll.frame
        let mid = (emptyHost.frame.height / 2).rounded()
        robot.layer.position = CGPoint(x: emptyHost.frame.width / 2, y: mid + 6)
        put(emptyTitle, 0, mid - 10, emptyHost.frame.width, align: .center)
        put(emptySub, 0, mid - 27, emptyHost.frame.width, align: .center)
    }

    private func showEmpty(_ on: Bool, allDone: Bool, finished: Int) {
        emptyHost.isHidden = !on
        guard on else { robot.stop(); return }
        emptyTitle.stringValue = showDone ? "Nothing finished yet" : allDone ? (offset == 0 ? "All done for today" : "All done") : "Nothing planned"
        emptySub.stringValue = showDone ? "" : allDone ? "\(finished) finished" : "Type below to add a task"
        robot.dance(allDone)  // celebrates; otherwise just stands
    }

    // MARK: The box

    /// Adds a task from the box or from a note line, and says where it went when that's not the list on show.
    func add(_ text: String, fromNote: Bool = false) {
        guard let t = planner.add(text, on: dayKey(in: fromNote ? 0 : offset)) else {
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { NSSound.beep() }  // only a date, no task
            return
        }
        if !fromNote { field.stringValue = ""; preview() }
        if let r = rows.subviews.first(where: { ($0 as? TaskRow)?.todo.id == t.id }) {
            r.alphaValue = 0
            fade(r, to: 1, duration: 0.3)
            rows.scrollToVisible(r.frame)
        }
        let off = dayOffset(t.day)
        guard off != offset || fromNote else { return }
        setHint("checkmark.circle.fill", "Added to \(whenText(off, t.due))", show: off != offset ? off : nil)
        toastWork = after(5) { [weak self] in self?.setHint(nil) }
    }

    func focusField() {
        window?.makeKey()  // the island takes typing without pulling you out of the app you're in
        window?.makeFirstResponder(field)
    }

    private func preview() {
        let s = field.stringValue, p = Parse(s)
        keycap.stringValue = s.isEmpty ? "⌥N" : "↩"
        // Tint the words read as the day and time
        if let ed = field.currentEditor() as? NSTextView, let lm = ed.layoutManager {
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (ed.string as NSString).length))
            for r in p.ranges {
                lm.addTemporaryAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.45), forCharacterRange: r)
            }
        }
        guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { setHint(nil); return }
        let off = p.day.map { dayOffset(dayKey($0)) } ?? offset
        setHint(p.due == nil ? "calendar" : "bell.fill", p.title.isEmpty ? "…" : p.title, whenText(off, p.due), key: "↩ add  ·  esc clear")
    }

    /// The line above the box; `nil` hides it.
    private func setHint(_ icon: String?, _ title: String = "", _ detail: String = "", key: String = "", show day: Int? = nil) {
        toastWork?.cancel()
        let on = icon != nil
        [hint, hintIcon].forEach { $0.isHidden = !on }
        hintKey.isHidden = !on || key.isEmpty
        show.isHidden = day == nil
        if let day { showOffset = day }
        if let icon {
            hintIcon.image = sym(icon, 10, .semibold)
            hintIcon.contentTintColor = icon == "checkmark.circle.fill" ? .systemGreen : white(0.5)
            let s = NSMutableAttributedString(string: title, attributes: [.foregroundColor: white(0.9), .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)])
            if !detail.isEmpty {
                s.append(NSAttributedString(string: "  ·  " + detail, attributes: [.foregroundColor: white(0.5), .font: NSFont.systemFont(ofSize: 11.5, weight: .medium)]))
            }
            let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingMiddle
            s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: s.length))
            hint.attributedStringValue = s
            hintKey.stringValue = key
        }
        layoutList()
    }

    private func styleBox(focused: Bool) {
        box.layer!.backgroundColor = white(focused ? 0.09 : 0.06).cgColor
        box.layer!.borderColor = white(focused ? 0.14 : 0).cgColor
    }

    func controlTextDidChange(_ n: Notification) { preview() }
    func controlTextDidEndEditing(_ n: Notification) { styleBox(focused: false) }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool {
        switch s {
        case #selector(insertNewline(_:)):
            add(field.stringValue)
            return true
        case #selector(cancelOperation(_:)):  // Esc clears the box, or closes the island once it's empty
            if field.stringValue.isEmpty { onEscape() } else { field.stringValue = ""; preview() }
            return true
        default:
            return false
        }
    }
}

/// "To do 3 | Done 1": which half of the day's list is on show.
final class Tabs: NSView {
    var onPick: (Bool) -> Void = { _ in }  // true for Done
    private let a = NSTextField(labelWithString: ""), b = NSTextField(labelWithString: "")
    private let knob = CALayer()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        wantsLayer = true; layer!.cornerRadius = 8; layer!.backgroundColor = white(0.07).cgColor
        knob.cornerRadius = 6; knob.backgroundColor = white(0.15).cgColor
        layer!.addSublayer(knob)
        addSubview(a); addSubview(b)
        setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(todo: Int, done: Int, showingDone: Bool) {
        a.attributedStringValue = segment("To do", todo, on: !showingDone)
        b.attributedStringValue = segment("Done", done, on: showingDone)
        let aw = ceil(a.fittingSize.width) + 18, bw = ceil(b.fittingSize.width) + 18
        put(a, 2, 11, aw, align: .center); put(b, 2 + aw, 11, bw, align: .center)
        frame.size.width = aw + bw + 4
        knob.frame = CGRect(x: showingDone ? 2 + aw : 2, y: 2, width: showingDone ? bw : aw, height: 18)  // slides across
        setAccessibilityLabel(showingDone ? "Showing \(done) done. Show to do" : "Showing \(todo) to do. Show done")
    }

    private func segment(_ name: String, _ n: Int, on: Bool) -> NSAttributedString {
        let s = NSMutableAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                                                                     .foregroundColor: white(on ? 0.95 : 0.5)])
        s.append(NSAttributedString(string: "  \(n)", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
                                                                  .foregroundColor: white(on ? 0.55 : 0.32)]))
        return s
    }

    override func hitTest(_ p: NSPoint) -> NSView? { frame.contains(p) ? self : nil }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { onPick(convert(e.locationInWindow, from: nil).x > b.frame.minX) }
    override func accessibilityPerformPress() -> Bool { onPick(knob.frame.minX < b.frame.minX); return true }
}

// MARK: - A task

/// One task: tick, title, and its reminder underneath. Double-click to edit; ⋯ or right-click for the rest.
final class TaskRow: FlippedView, NSTextFieldDelegate {
    let todo: Todo
    private(set) var editing: InputField?
    private unowned let planner: Planner
    private let tick: TickView
    private let title = label("", 13, .medium)
    private var more: IconButton!

    init(_ t: Todo, width: CGFloat, planner: Planner) {
        todo = t; self.planner = planner
        tick = TickView(done: t.done)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: t.due == nil ? 34 : 46))
        tick.frame.origin = NSPoint(x: 0, y: 8)
        tick.setAccessibilityLabel(t.title)
        tick.action = { [unowned self] in self.toggle() }
        styleTitle(done: t.done)
        put(title, 27, 17, width - 27 - 30)
        var views: [NSView] = [tick, title]
        if let due = t.due {
            let late = !t.done && due < Date(), color = late ? NSColor.systemRed : white(0.45)
            let bell = NSImageView(image: sym("bell.fill", 9, .medium))
            bell.contentTintColor = color
            bell.frame = NSRect(x: 27, y: 27, width: 11, height: 12)
            let when = label((late ? "Overdue · " : "") + dueText(due), 11, .medium, color)
            put(when, 41, 33, width - 41 - 30)
            views += [bell, when]
        }
        more = IconButton("ellipsis", size: 22, point: 12, label: "More for \(t.title)") { [unowned self] in
            self.actions().popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self.more)
        }
        more.image.contentTintColor = white(0.6)
        more.frame.origin = NSPoint(x: width - 22, y: 6)
        more.isHidden = true
        views += [more, dashedLine(0, frame.height - 1, width)]
        views.forEach(addSubview)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func styleTitle(done: Bool) {
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        title.attributedStringValue = NSAttributedString(string: todo.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: white(done ? 0.4 : 0.92), .paragraphStyle: p,
            .strikethroughStyle: done ? NSUnderlineStyle.single.rawValue : 0, .strikethroughColor: white(0.4)])
    }

    private func toggle() {
        tick.done.toggle()
        styleTitle(done: tick.done)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        let id = todo.id, done = tick.done
        after(0.45) { [planner] in planner.setDone(id, done) }  // the tick shows before the row moves lists
    }

    private func actions() -> NSMenu {
        let m = NSMenu(), id = todo.id, p = planner
        if !todo.done {
            m.addItem(ActionItem("Edit", symbol: "pencil") { [weak self] in self?.startEditing() })
            let cal = Calendar.current, now = Date(), sub = NSMenu()
            sub.addItem(ActionItem("In 1 Hour", symbol: "clock") { p.remind(id, at: Date().addingTimeInterval(3600)) })
            let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
            if evening > now { sub.addItem(ActionItem("This Evening, \(dueText(evening))", symbol: "sunset") { p.remind(id, at: evening) }) }
            let morning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: now)!)!
            sub.addItem(ActionItem("Tomorrow, \(morning.formatted(date: .omitted, time: .shortened))", symbol: "sunrise") {
                p.remind(id, at: morning)
            })
            if todo.due != nil {
                sub.addItem(.separator())
                sub.addItem(ActionItem("No Reminder", symbol: "bell.slash") { p.remind(id, at: nil) })
            }
            let remind = NSMenuItem(title: "Remind Me", action: nil, keyEquivalent: "")
            remind.image = NSImage(systemSymbolName: "bell", accessibilityDescription: nil)
            remind.submenu = sub
            m.addItem(remind)
            let isToday = todo.day == dayKey(Date())
            m.addItem(ActionItem(isToday ? "Move to Tomorrow" : "Move to Today", symbol: isToday ? "arrow.turn.down.right" : "arrow.uturn.backward") {
                p.move(id, to: dayKey(in: isToday ? 1 : 0))
            })
            m.addItem(.separator())
        }
        m.addItem(ActionItem("Delete", symbol: "trash") { p.delete(id) })
        return m
    }

    // MARK: Editing in place

    func startEditing() {
        guard editing == nil, !todo.done, let w = window else { return }
        let f = inputField("", 13, .medium)
        f.stringValue = todo.title
        f.frame = NSRect(x: title.frame.minX, y: title.frame.minY, width: title.frame.width, height: f.fittingSize.height)
        f.delegate = self
        title.isHidden = true
        addSubview(f)
        editing = f
        w.makeKey()
        w.makeFirstResponder(f)
        f.currentEditor()?.selectAll(nil)
    }

    private func finishEditing(save: Bool) {
        guard let f = editing else { return }
        editing = nil
        let text = f.stringValue
        window?.makeFirstResponder(nil)
        f.removeFromSuperview()
        title.isHidden = false
        if save, text != todo.title { planner.edit(todo.id, to: text) }  // a day or time typed in moves it
    }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool {
        if s == #selector(insertNewline(_:)) { finishEditing(save: true); return true }
        if s == #selector(cancelOperation(_:)) { finishEditing(save: false); return true }
        return false
    }
    func controlTextDidEndEditing(_ n: Notification) { finishEditing(save: true) }  // clicked elsewhere

    // MARK: Mouse

    override func hitTest(_ p: NSPoint) -> NSView? {
        let v = super.hitTest(p)
        if editing != nil || v === tick || v === more { return v }
        return v == nil ? nil : self
    }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { if e.clickCount == 2 { startEditing() } }
    override func menu(for event: NSEvent) -> NSMenu? { actions() }
    override func mouseEntered(with e: NSEvent) { more.isHidden = false }
    override func mouseExited(with e: NSEvent) { more.isHidden = true }
}

/// The round checkbox in front of a task.
final class TickView: NSView {
    var action: () -> Void = {}
    var done: Bool { didSet { style() } }
    private var hover = false { didSet { style() } }
    private let ring = CAShapeLayer()
    private let mark = NSImageView(image: sym("checkmark", 9, .heavy))

    init(done: Bool) {
        self.done = done
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        wantsLayer = true
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 1, dy: 1), transform: nil)
        ring.lineWidth = 1.5
        layer!.addSublayer(ring)
        mark.frame = bounds
        mark.contentTintColor = .black
        addSubview(mark)
        style()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityElement(true); setAccessibilityRole(.checkBox)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func style() {
        ring.fillColor = done ? white(0.9).cgColor : hover ? white(0.08).cgColor : nil
        ring.strokeColor = (done ? white(0.9) : white(hover ? 0.8 : 0.4)).cgColor
        mark.isHidden = !done
        setAccessibilityValue(done)
    }

    override func hitTest(_ p: NSPoint) -> NSView? { frame.insetBy(dx: -4, dy: -4).contains(p) ? self : nil }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func mouseUp(with e: NSEvent) { if bounds.insetBy(dx: -4, dy: -4).contains(convert(e.locationInWindow, from: nil)) { action() } }
    override func accessibilityPerformPress() -> Bool { action(); return true }
}

// MARK: - Notepad: the day's scratch note

/// Saves as you type, one plain-text file a day. ⌘↩ turns the line you're on into a task.
final class NoteCard: FlippedView, NSTextViewDelegate {
    let text = NoteTextView(usingTextLayoutManager: false)
    var onTask: (String) -> Void = { _ in }
    private unowned let planner: Planner
    private let scroll = NSScrollView()
    private let date = label("", 11.5, .medium, white(0.45))
    private let placeholder = NSTextField(wrappingLabelWithString: "Jot things down.\n⌘↩ turns a line into a task.")
    private let words = label("", 10.5, .medium, white(0.4))
    private var day = "", saveWork: Task<Void, Never>?

    init(frame: NSRect, planner: Planner) {
        self.planner = planner
        super.init(frame: frame)
        styleCard(self)
        let w = frame.width, h = frame.height
        let title = label("Notepad", 14, .semibold); put(title, 14, 24, 100)
        put(date, w - 94, 24, 80, align: .right)

        scroll.frame = NSRect(x: 14, y: 42, width: w - 28, height: h - 42 - 38)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay; scroll.scrollerKnobStyle = .light; scroll.autohidesScrollers = true
        let size = scroll.contentSize
        text.frame = NSRect(origin: .zero, size: size)
        text.minSize = NSSize(width: 0, height: size.height)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.textContainer!.containerSize = NSSize(width: size.width, height: .greatestFiniteMagnitude)
        text.textContainer!.widthTracksTextView = true
        text.textContainer!.lineFragmentPadding = 0
        text.textContainerInset = .zero
        text.drawsBackground = false; text.isRichText = false; text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
        let para = NSMutableParagraphStyle(); para.lineSpacing = 3
        text.defaultParagraphStyle = para
        text.typingAttributes = [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: white(0.88), .paragraphStyle: para]
        text.insertionPointColor = .white
        text.delegate = self
        text.onCommandReturn = { [unowned self] in self.lineToTask() }
        scroll.documentView = text

        placeholder.font = .systemFont(ofSize: 12.5); placeholder.textColor = white(0.3)
        placeholder.frame = NSRect(x: 14, y: 42, width: w - 28, height: 40)
        let hint = label("⌘↩ line → task", 10.5, .medium, white(0.4))
        put(words, 14, h - 16, 80); put(hint, w - 114, h - 16, 100, align: .right)
        ([title, date, scroll, placeholder, dashedLine(14, h - 31, w - 28), words, hint] as [NSView]).forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Shows today's note, fresh from disk (another display's island may have changed it), unless you're typing in it.
    func reload() {
        guard window?.firstResponder !== text else { return }
        flush()
        day = dayKey(Date())
        text.textStorage!.setAttributedString(NSAttributedString(string: planner.note(day), attributes: text.typingAttributes))
        date.stringValue = Date().formatted(.dateTime.day().month(.abbreviated))
        refresh()
    }

    /// Saves now if a save is waiting.
    func flush() {
        guard let w = saveWork else { return }
        w.cancel(); saveWork = nil
        planner.setNote(text.string, day)
    }

    func textDidChange(_ n: Notification) {
        refresh()
        saveWork?.cancel()
        saveWork = after(0.6) { [weak self] in self?.flush() }
    }

    private func refresh() {
        placeholder.isHidden = !text.string.isEmpty
        let n = text.string.split(whereSeparator: \.isWhitespace).count
        words.stringValue = n == 1 ? "1 word" : "\(n) words"
    }

    private func lineToTask() {
        let s = text.string as NSString, r = s.lineRange(for: text.selectedRange())
        let line = s.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^([-*•]|\[ ?\])\s+"#, with: "", options: .regularExpression)  // a list marker isn't part of it
        guard !line.isEmpty else { NSSound.beep(); return }
        onTask(line)
        guard let lm = text.layoutManager else { return }
        lm.addTemporaryAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.3), forCharacterRange: r)
        after(0.8) { [text] in
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (text.string as NSString).length))
        }
    }
}

final class NoteTextView: NSTextView {
    var onCommandReturn: () -> Void = {}
    var onEscape: () -> Void = {}

    override func keyDown(with e: NSEvent) {
        if [36, 76].contains(e.keyCode), e.modifierFlags.contains(.command) { onCommandReturn() } else { super.keyDown(with: e) }
    }
    override func cancelOperation(_ sender: Any?) { onEscape() }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
}

// MARK: - Due alert

/// What the collapsed island shows when a task comes due: the robot waving a bell, the task, Snooze and Done.
/// `r` is the island's rect in window coordinates.
func alertViews(_ t: Todo, in r: CGRect, snooze: @escaping () -> Void, done: @escaping () -> Void) -> [NSView] {
    let avatar = NSView(frame: NSRect(x: r.minX + 16, y: r.minY + 14, width: 52, height: 52))
    avatar.wantsLayer = true; avatar.layer!.cornerRadius = 14; avatar.layer!.backgroundColor = white(0.14).cgColor
    let robot = Robot()
    robot.layer.position = CGPoint(x: 26, y: 8)
    robot.layer.setAffineTransform(CGAffineTransform(scaleX: 1.5, y: 1.5))
    robot.setAntenna(.systemOrange)
    robot.loop([.wave1, .wave2], period: 0.8)
    avatar.layer!.addSublayer(robot.layer)
    let badge = NSView(frame: NSRect(x: avatar.frame.minX + 38, y: avatar.frame.minY - 5, width: 20, height: 20))  // over the corner
    badge.wantsLayer = true; badge.layer!.cornerRadius = 10; badge.layer!.backgroundColor = NSColor.systemOrange.cgColor
    badge.layer!.borderWidth = 2.5; badge.layer!.borderColor = NSColor.black.cgColor
    let bell = NSImageView(image: sym("bell.fill", 8, .bold))
    bell.contentTintColor = .black; bell.frame = badge.bounds
    badge.addSubview(bell)

    let x = avatar.frame.maxX + 12, w = r.maxX - 16 - x
    let title = label(t.title, 14.5, .semibold); put(title, x, r.minY + 58, w)
    let when = label("Due \(dueText(t.due ?? Date()))", 12, .medium, white(0.5)); put(when, x, r.minY + 40, w)
    let later = PillButton("5 min", symbol: "moon.zzz.fill", color: white(0.18), width: 66)
    later.frame.origin = NSPoint(x: x, y: r.minY + 12)
    later.toolTip = "Remind me again in 5 minutes"
    later.action = snooze
    let ok = PillButton("Done", symbol: "checkmark", color: .systemOrange, width: 62)
    ok.frame.origin = NSPoint(x: x + 72, y: r.minY + 12)
    ok.action = done
    return [avatar, badge, title, when, later, ok]
}
