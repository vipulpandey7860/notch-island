// Coding agents in the notch. Claude Code reports through its hooks (working, waiting for you, done) and asks here
// before it runs a tool; Codex reports when it finishes a turn (its `notify` setting). Both reach us through curl,
// which ships with macOS, over a Unix socket in your Library folder that only you can open. If Notch Island isn't
// running, the hooks do nothing and the agents behave exactly as before.
import AppKit

final class Agents {
    struct Session {
        let project: String
        let since: Date
        var waiting = false
    }
    /// A Claude Code permission prompt, waiting for an answer from the notch.
    struct Request {
        let id: Int
        let session: String, project: String
        let tool: String, summary: String
        /// The summary is the whole request: nothing cut off or left out. Only then may the notch offer Allow;
        /// otherwise you review it in the terminal, where Claude Code shows all of it.
        let complete: Bool
        let answer: (Data) -> Void
    }

    static let socketPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Notch Island/agents.sock").path
    /// Hand a prompt back to the terminal after this long, before curl gives up (the hook allows 120 s).
    static let requestTimeout = 110.0
    /// Only say "finished" for turns at least this long; quick answers you watched happen anyway.
    static let worthMentioning = 20.0

    private(set) var sessions: [String: Session] = [:]  // Claude Code sessions working or waiting, by session id
    var onChange: () -> Void = {}
    var onNote: (_ title: String, _ detail: String, _ done: Bool) -> Void = { _, _, _ in }
    var onRequest: (Request) -> Void = { _ in }
    var onRequestGone: (Int) -> Void = { _ in }
    private var pending: [Int: Request] = [:]
    private var nextID = 1
    private let server = SocketServer()

    func start(path: String = Agents.socketPath) {
        server.start(path: path) { [weak self] route, body, reply in
            if let self { self.handle(route, body, reply) } else { reply(Data()) }
        }
    }

    /// The session that's been at it longest, for the island's ear.
    var longest: Session? { sessions.values.min { $0.since < $1.since } }

    /// `nil` hands the prompt back to the terminal.
    func answer(_ id: Int, allow: Bool?) {
        guard let r = pending.removeValue(forKey: id) else { return }
        r.answer(allow.map(Self.decision) ?? Data())
        sessions[r.session]?.waiting = false
        onChange()
    }

    private func handle(_ route: String, _ body: Data, _ reply: @escaping (Data) -> Void) {
        let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if route == "/codex" {
            reply(Data())
            let last = j["last-assistant-message"] as? String ?? j["last_assistant_message"] as? String ?? ""
            let first = last.split(separator: "\n").first.map(String.init) ?? ""
            onNote("Codex finished", (j["cwd"] as? String).map(Self.project) ?? (first.isEmpty ? "Your turn" : first), true)
            return
        }
        let sid = j["session_id"] as? String ?? "", name = Self.project(j["cwd"] as? String ?? "")
        switch j["hook_event_name"] as? String {
        case "UserPromptSubmit":
            reply(Data())  // anything printed here would be added to Claude's context
            sessions[sid] = Session(project: name, since: Date())
            onChange()
        case "PermissionRequest":
            let tool = j["tool_name"] as? String ?? "a tool", input = j["tool_input"] as? [String: Any] ?? [:]
            let id = nextID
            nextID += 1
            let (summary, complete) = Self.summary(tool, input, cwd: j["cwd"] as? String ?? "")
            let r = Request(id: id, session: sid, project: name, tool: tool, summary: summary, complete: complete, answer: reply)
            pending[id] = r
            if sessions[sid] == nil { sessions[sid] = Session(project: name, since: Date()) }
            sessions[sid]?.waiting = true
            onChange()
            onRequest(r)
            after(Self.requestTimeout) { [weak self] in
                guard let self, self.pending[id] != nil else { return }
                self.answer(id, allow: nil)
                self.onRequestGone(id)
            }
        case "Notification":
            reply(Data())
            if j["notification_type"] as? String == "idle_prompt" { onNote("Claude is waiting for you", name, false) }
        case "Stop":
            reply(Data())
            let took = sessions.removeValue(forKey: sid).map { Date().timeIntervalSince($0.since) }
            onChange()
            if took ?? 0 >= Self.worthMentioning { onNote("Claude finished", "\(name) · \(durationText(took!))", true) }
        case "SessionEnd":
            reply(Data())
            sessions.removeValue(forKey: sid)
            for r in pending.values where r.session == sid {
                answer(r.id, allow: nil)
                onRequestGone(r.id)
            }
            onChange()
        default:
            reply(Data())
        }
    }

    static func project(_ cwd: String) -> String { cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent }

    /// What a permission prompt is about, in a line ("npm test", "Edit Sources/App.swift"), and whether that line is
    /// all of it. Not complete: a command over several lines or too long to show, a file outside the project (shown
    /// with its full path), and any other tool, whose arguments the line leaves out.
    static func summary(_ tool: String, _ input: [String: Any], cwd: String) -> (String, complete: Bool) {
        func fits(_ s: String) -> Bool {  // in the heads-up's title, without being cut off
            (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14.5, weight: .semibold)]).width <= 310
        }
        func file(_ verb: String) -> (String, complete: Bool) {
            let path = input["file_path"] as? String ?? input["notebook_path"] as? String ?? ""
            let root = cwd.hasSuffix("/") ? cwd : cwd + "/"
            if !cwd.isEmpty, path.hasPrefix(root), !path.contains("/../") {
                let s = "\(verb) \(path.dropFirst(root.count))"
                return (s, fits(s))
            }
            return ("\(verb) \((path as NSString).abbreviatingWithTildeInPath)", false)  // outside the project
        }
        switch tool {
        case "Bash":
            let cmd = (input["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = cmd.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > 1 { return ("\(lines[0]) (+\(lines.count - 1) more lines)", false) }
            return (cmd.isEmpty ? "Run a command" : cmd, !cmd.isEmpty && fits(cmd))
        case "Edit", "MultiEdit", "NotebookEdit": return file("Edit")
        case "Write": return file("Write")
        case "Read": return file("Read")
        case "WebFetch":
            let s = "Fetch \(input["url"] as? String ?? "")"
            return (s, fits(s))
        case "WebSearch":
            let s = "Search for “\(input["query"] as? String ?? "")”"
            return (s, fits(s))
        default:
            guard tool.hasPrefix("mcp__") else { return (tool, false) }
            let parts = tool.split(separator: "_")  // mcp__server__tool
            return ("\(parts.dropFirst().first ?? "MCP"): \(parts.last ?? "")", false)
        }
    }

    static func decision(_ allow: Bool) -> Data {
        var d: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { d["message"] = "Denied from Notch Island." }
        return try! JSONSerialization.data(withJSONObject: ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": d]])
    }
}

// MARK: - The socket

/// A tiny HTTP server on a Unix socket: one request per connection, answered whenever `reply` is called (on the main
/// queue). REVIEW: hand-rolled HTTP; it only has to understand what curl sends.
final class SocketServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "notch-island.agents", attributes: .concurrent)

    func start(path: String, handle: @escaping (String, Data, @escaping (Data) -> Void) -> Void) {
        unlink(path)  // left over from the last run
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard fd >= 0, bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else { close(fd); return }  // only you can connect
        queue.async {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { if errno == EINTR { continue } else { return } }
                self.queue.async { self.serve(c, handle) }
            }
        }
    }

    private func serve(_ c: Int32, _ handle: @escaping (String, Data, @escaping (Data) -> Void) -> Void) {
        var buf = Data(), chunk = [UInt8](repeating: 0, count: 16384)
        let sep = Data("\r\n\r\n".utf8), limit = 1 << 20
        func more() -> Bool {
            let n = read(c, &chunk, chunk.count)
            if n > 0 { buf.append(chunk, count: n) }
            return n > 0 && buf.count < limit
        }
        while buf.range(of: sep) == nil { guard more() else { close(c); return } }
        let end = buf.range(of: sep)!
        let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self)
        let path = head.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
        let length = head.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        while buf.count - end.upperBound < length { guard more() else { close(c); return } }
        let body = buf.subdata(in: end.upperBound..<end.upperBound + length)
        DispatchQueue.main.async {
            var replied = false
            handle(path, body) { reply in
                guard !replied else { return }
                replied = true
                self.queue.async {
                    let out = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(reply.count)\r\nConnection: close\r\n\r\n".utf8) + reply
                    out.withUnsafeBytes { _ = write(c, $0.baseAddress, out.count) }
                    close(c)
                }
            }
        }
    }
}

// MARK: - Connecting the agents

/// Adds Notch Island's hooks to Claude Code's settings and Codex's config, and takes them out again. The first time it
/// touches a file it keeps a copy of how it was, next to it.
enum AgentHooks {
    enum Failure: LocalizedError {
        case unreadable(URL), codexHasNotify
        var errorDescription: String? {
            switch self {
            case .unreadable(let u): return "\(u.path) isn't valid JSON, so Notch Island left it alone."
            case .codexHasNotify: return "Codex already runs a program when it finishes (the notify line in ~/.codex/config.toml). Notch Island left it alone."
            }
        }
    }

    static let marker = "Notch Island/agents.sock"
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var claudeFile: URL { home.appendingPathComponent(".claude/settings.json").resolvingSymlinksInPath() }
    static var codexFile: URL { home.appendingPathComponent(".codex/config.toml").resolvingSymlinksInPath() }
    static var codexInstalled: Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path) }
    static var claudeConnected: Bool { (try? String(contentsOf: claudeFile, encoding: .utf8))?.contains(marker) == true }
    static var codexConnected: Bool { (try? String(contentsOf: codexFile, encoding: .utf8))?.contains(marker) == true }

    /// The events Notch Island listens to, and how long each hook may take: a permission prompt waits for you.
    static let claudeEvents: [(String, Int)] = [("UserPromptSubmit", 5), ("PermissionRequest", 120), ("Notification", 5),
                                                ("Stop", 5), ("SessionEnd", 5)]

    static func claudeCommand(timeout: Int) -> String {
        "curl -s -m \(timeout) -H 'Expect:' --unix-socket \"$HOME/Library/Application Support/\(marker)\" --data-binary @- http://localhost/claude || true"
    }
    static let codexComment = "# Notch Island: tells the notch when Codex finishes"
    static let codexLine = #"notify = ["sh", "-c", "curl -s -m 5 -H 'Expect:' --unix-socket \"$HOME/Library/Application Support/Notch Island/agents.sock\" --data-binary \"$1\" http://localhost/codex >/dev/null 2>&1 || true", "notch-island"]"#

    static func setClaude(_ on: Bool, file url: URL = claudeFile) throws {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let r = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.unreadable(url) }
            root = r
            try keepOriginal(url)
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in claudeEvents {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { group in
                !(group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
            }
            if on { groups.append(["hooks": [["type": "command", "command": claudeCommand(timeout: timeout), "timeout": timeout + 5]]]) }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: url, options: .atomic)
    }

    static func setCodex(_ on: Bool, file url: URL = codexFile) throws {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n").filter { !$0.contains(marker) && $0 != codexComment }
        if on {
            guard !lines.contains(where: { $0.range(of: #"^\s*notify\s*="#, options: .regularExpression) != nil }) else {
                throw Failure.codexHasNotify
            }
            lines.insert(contentsOf: [codexComment, codexLine, ""], at: 0)  // a top-level key: before any [table]
        } else if lines.first?.isEmpty == true {
            lines.removeFirst()
        }
        if !text.isEmpty { try keepOriginal(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// settings.json → settings.json.before-notch-island, once.
    private static func keepOriginal(_ url: URL) throws {
        let copy = url.appendingPathExtension("before-notch-island")
        if !FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.copyItem(at: url, to: copy) }
    }
}

// MARK: - Self-check (part of `NotchIsland --selftest`)

extension Agents {
    static func selfTest(in dir: URL) {
        // A permission prompt from Claude Code, through curl and the socket, answered Allow from the notch
        let agents = Agents(), sock = "/tmp/notch-island-test-\(getpid()).sock"  // socket paths max out at 104 bytes
        defer { unlink(sock) }
        var asked: Request?
        agents.onRequest = { asked = $0; agents.answer($0.id, allow: true) }
        agents.start(path: sock)
        let prompt = #"{"session_id":"s1","cwd":"/tmp/demo","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let out = curl(sock, route: "claude", body: prompt)
        precondition(asked?.summary == "npm test" && asked?.project == "demo", "request read")
        // Allow only when the notch shows the whole request
        precondition(asked?.complete == true, "a short command is complete")
        let cwd = "/Users/me/app"
        precondition(!summary("Bash", ["command": "ls\nrm -rf ~"], cwd: cwd).complete, "a second line is hidden")
        precondition(!summary("Bash", ["command": String(repeating: "echo ok && ", count: 20)], cwd: cwd).complete, "too long to show")
        precondition(summary("Edit", ["file_path": "/Users/me/app/Sources/A.swift"], cwd: cwd) == ("Edit Sources/A.swift", true), "in the project")
        precondition(!summary("Read", ["file_path": "/Users/me/.ssh/id_rsa"], cwd: cwd).complete, "outside the project")
        precondition(!summary("Edit", ["file_path": "/Users/me/app/../.zshrc"], cwd: cwd).complete, "climbs out of the project")
        precondition(!summary("mcp__github__create_issue", [:], cwd: cwd).complete, "arguments left out")
        let reply = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: [String: Any]]
        precondition((reply?["hookSpecificOutput"]?["decision"] as? [String: String])?["behavior"] == "allow", "answer sent: \(out)")
        precondition(curl(sock, route: "claude", body: #"{"session_id":"s2","cwd":"/x/y","hook_event_name":"UserPromptSubmit"}"#).isEmpty
                     && agents.sessions["s2"]?.project == "y", "a prompt starts a session and prints nothing")

        // Connecting keeps what's already there, and disconnecting takes out only ours
        let claude = dir.appendingPathComponent("settings.json")
        try! #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#.write(to: claude, atomically: true, encoding: .utf8)
        try! AgentHooks.setClaude(true, file: claude)
        var j = try! JSONSerialization.jsonObject(with: Data(contentsOf: claude)) as! [String: Any]
        var hooks = j["hooks"] as! [String: [Any]]
        precondition(j["model"] as? String == "opus" && hooks["Stop"]?.count == 2 && hooks["PermissionRequest"]?.count == 1, "connect")
        precondition(FileManager.default.fileExists(atPath: claude.path + ".before-notch-island"), "original kept")
        try! AgentHooks.setClaude(false, file: claude)
        j = try! JSONSerialization.jsonObject(with: Data(contentsOf: claude)) as! [String: Any]
        hooks = j["hooks"] as! [String: [Any]]
        precondition(hooks.keys.sorted() == ["Stop"] && hooks["Stop"]?.count == 1, "disconnect")

        let codex = dir.appendingPathComponent("config.toml")
        try! "model = \"o4\"\n\n[profiles.x]\nmodel = \"y\"\n".write(to: codex, atomically: true, encoding: .utf8)
        try! AgentHooks.setCodex(true, file: codex)
        let toml = try! String(contentsOf: codex, encoding: .utf8)
        precondition(toml.components(separatedBy: "\n")[1].hasPrefix("notify = ") && toml.contains("[profiles.x]"), "codex connect: before any table")
        try! AgentHooks.setCodex(false, file: codex)
        precondition(try! String(contentsOf: codex, encoding: .utf8) == "model = \"o4\"\n\n[profiles.x]\nmodel = \"y\"\n", "codex disconnect")
    }

    /// Runs curl like the hooks do, turning the main queue until it's done (the socket answers on it).
    private static func curl(_ sock: String, route: String, body: String) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["-s", "-m", "5", "-H", "Expect:", "--unix-socket", sock, "--data-binary", body, "http://localhost/\(route)"]
        p.standardOutput = pipe
        try! p.run()
        while p.isRunning { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
