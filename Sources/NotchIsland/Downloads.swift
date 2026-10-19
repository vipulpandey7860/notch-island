// Browser downloads landing in ~/Downloads. Safari and Chrome publish progress for the file they're
// downloading (that's how Finder draws its progress bars), and we subscribe to it the same way.
import Foundation

/// `@unchecked Sendable`: progress callbacks arrive on any thread, but all they do is hop to the main queue.
final class Downloads: @unchecked Sendable {
    var onChange: () -> Void = {}
    var onFinished: (URL) -> Void = { _ in }
    private var active: [ObjectIdentifier: Progress] = [:]
    private var watches: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var shownPercent: [ObjectIdentifier: Int] = [:]  // to report whole-percent steps only
    private var subscriber: Any?

    var count: Int { active.count }
    /// Average progress of everything downloading, 0...1.
    var fraction: Double { active.isEmpty ? 0 : active.values.map(\.fractionCompleted).reduce(0, +) / Double(active.count) }

    // REVIEW: relies on the browser publishing progress for ~/Downloads (Safari and Chrome do;
    // Firefox may not). Untested against every browser.
    func start() {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        subscriber = Progress.addSubscriber(forFileURL: dir) { [weak self] p in
            DispatchQueue.main.async { self?.add(p) }
            return { DispatchQueue.main.async { self?.finish(p) } }
        }
    }

    private func add(_ p: Progress) {
        let id = ObjectIdentifier(p)
        active[id] = p
        watches[id] = p.observe(\.fractionCompleted) { [weak self] p, _ in
            let percent = Int(p.fractionCompleted * 100)
            DispatchQueue.main.async {
                guard let self, self.active[id] != nil, self.shownPercent[id] != percent else { return }
                self.shownPercent[id] = percent
                self.onChange()
            }
        }
        onChange()
    }

    private func finish(_ p: Progress) {
        let id = ObjectIdentifier(p)
        guard active.removeValue(forKey: id) != nil else { return }
        watches[id] = nil
        shownPercent[id] = nil
        onChange()
        guard !p.isCancelled, let url = p.fileURL else { return }
        // The browser renames "file.download" / "file.crdownload" a moment after it's done
        let final = ["download", "crdownload", "part"].contains(url.pathExtension) ? url.deletingPathExtension() : url
        after(1) { if FileManager.default.fileExists(atPath: final.path) { self.onFinished(final) } }
    }
}
