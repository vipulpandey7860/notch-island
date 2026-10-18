// Battery, calendar and network speed.
import AppKit
import EventKit
import IOKit.ps

// MARK: - Battery

struct Power: Equatable {
    var level = 100, charging = false, plugged = false, hasBattery = false
}

func readPower() -> Power {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return Power() }
    for src in list {
        guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
        let now = d[kIOPSCurrentCapacityKey] as? Int ?? 0, full = d[kIOPSMaxCapacityKey] as? Int ?? 100
        return Power(level: now * 100 / max(full, 1), charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                     plugged: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue, hasBattery: true)
    }
    return Power()
}

// MARK: - Calendar

final class Meetings {
    private let store = EKEventStore()
    private(set) var next: EKEvent?
    var onChange: () -> Void = {}

    func start() {
        store.requestFullAccessToEvents { [weak self] _, _ in DispatchQueue.main.async { self?.refresh() } }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    /// The next timed event in the coming 12 hours. One that already started stays for its first
    /// 10 minutes ("now"), then gives way, so a long block doesn't hide the meeting after it.
    func refresh() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let found = store.events(matching: store.predicateForEvents(withStart: now.addingTimeInterval(-3600),
                                                                    end: now.addingTimeInterval(12 * 3600), calendars: nil))
        next = found
            .filter { !$0.isAllDay && $0.status != .canceled && $0.startDate > now.addingTimeInterval(-600) && $0.endDate > now }
            .min { $0.startDate < $1.startDate }
        onChange()
    }
}

/// "now", "in 4m", "in 1h 20m", or a clock time when it's further out.
func when(_ d: Date) -> String {
    let m = Int((d.timeIntervalSinceNow / 60).rounded(.up))
    if m <= 0 { return "now" }
    if m < 60 { return "in \(m)m" }
    if m < 180 { return m % 60 == 0 ? "in \(m / 60)h" : "in \(m / 60)h \(m % 60)m" }
    return d.formatted(date: .omitted, time: .shortened)
}

// MARK: - Network speed: diff the interface byte counters once a second, like Activity Monitor

final class NetSpeed {
    private var last: (rx: UInt64, tx: UInt64)?

    /// Bytes per second since the previous call; call it once a second.
    func sample() -> (down: UInt64, up: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0, ifap: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifap) == 0 {
            var p = ifap
            while let a = p?.pointee {
                // REVIEW: counts "en*" only (Wi-Fi/Ethernet) so traffic through a VPN tunnel isn't counted twice
                if a.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), String(cString: a.ifa_name).hasPrefix("en"),
                   let d = a.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                    rx += UInt64(d.ifi_ibytes); tx += UInt64(d.ifi_obytes)
                }
                p = a.ifa_next
            }
            freeifaddrs(ifap)
        }
        let prev = last
        last = (rx, tx)
        guard let l = prev else { return (0, 0) }
        // TODO: if_data counters are 32-bit and wrap every 4 GB (that second reads 0); read 64-bit ones via sysctl NET_RT_IFLIST2
        return (rx >= l.rx ? rx - l.rx : 0, tx >= l.tx ? tx - l.tx : 0)
    }
}

func rate(_ b: UInt64) -> String {
    b >= 1_000_000 ? String(format: "%.1f MB/s", Double(b) / 1e6) : "\(b / 1000) KB/s"
}
