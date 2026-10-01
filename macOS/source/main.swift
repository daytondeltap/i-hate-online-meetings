import AppKit
import Carbon
import Foundation
import Darwin

enum NTMode: Int {
    case fast = 0
    case adapter = 1
    case zoomLag = 2
    case zoomKick = 3
    case meetLag = 4
    case meetHold = 5
}

struct AdapterInfo {
    let label: String
    let device: String
}

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

@discardableResult
func shell(_ executable: String, _ args: [String], input: String? = nil) -> ShellResult {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("out"), errors = dir.appendingPathComponent("err"), stdin = dir.appendingPathComponent("in")
        try Data().write(to: output); try Data().write(to: errors)
        try (input ?? "").data(using: .utf8)!.write(to: stdin)
        let out = try FileHandle(forWritingTo: output), err = try FileHandle(forWritingTo: errors), inf = try FileHandle(forReadingFrom: stdin)
        defer { try? out.close(); try? err.close(); try? inf.close() }
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
        p.standardOutput = out; p.standardError = err; p.standardInput = inf
        try p.run(); p.waitUntilExit()
        return ShellResult(status: p.terminationStatus, stdout: (try? String(contentsOf: output, encoding: .utf8)) ?? "", stderr: (try? String(contentsOf: errors, encoding: .utf8)) ?? "")
    } catch { return ShellResult(status: 127, stdout: "", stderr: error.localizedDescription) }
}
func failure(_ message: String) -> NSError { NSError(domain: "ihatemeetings", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

func guardFile() throws -> String {
    var template = Array("/private/tmp/ihatemeetings.XXXXXX".utf8CString)
    guard let ptr = mkdtemp(&template) else { throw failure("Could not create recovery directory.") }
    let path = String(cString: ptr) + "/guard"
    try Data().write(to: URL(fileURLWithPath: path))
    return path
}
func shQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func appleQuote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

func ensureElevated() {
    if geteuid() == 0 { return }
    if CommandLine.arguments.contains("--elevated") { fputs("ihatemeetings requires administrator privileges.\n", stderr); exit(1) }
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
    let command = "/bin/sh -c " + shQuote("exec " + shQuote(exe) + " --elevated >/dev/null 2>&1 </dev/null &")
    let script = "do shell script " + appleQuote(command) + " with administrator privileges"
    _ = shell("/usr/bin/osascript", ["-e", script])
    exit(0)
}

final class PFController {
    private let anchor = "com.apple/ihatemeetings-\(getpid())"
    private var token: String?
    private var enabledByUs = false
    private var guardFlag: String?

    private func armCrashGuard() throws {
        if guardFlag != nil { return }
        let flag = try guardFile()
        guardFlag = flag
        let parent = getpid()
        var cleanup = "/sbin/pfctl -a \(shQuote(anchor)) -F all >/dev/null 2>&1"
        if enabledByUs, let token = token, !token.isEmpty { cleanup += "; /sbin/pfctl -X \(shQuote(token)) >/dev/null 2>&1" }
        cleanup += "; rm -f \(shQuote(flag)); rmdir \(shQuote(URL(fileURLWithPath: flag).deletingLastPathComponent().path))"
        let script = "while kill -0 \(parent) 2>/dev/null; do sleep 1; done; if [ -f \(shQuote(flag)) ]; then \(cleanup); fi"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try p.run()
    }

    private func disarmCrashGuard() {
        if let flag = guardFlag { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: flag).deletingLastPathComponent().path) }
        guardFlag = nil
    }

    func ensureEnabled() throws {
        if token != nil || guardFlag != nil { return }
        let root = shell("/sbin/pfctl", ["-sr"])
        guard root.status == 0 && root.stdout.contains("anchor \"com.apple/*\"") else {
            throw failure("The active PF configuration does not invoke com.apple/* anchors. No system firewall configuration was changed.")
        }
        let r = shell("/sbin/pfctl", ["-E"])
        guard r.status == 0 else { throw NSError(domain: "ihatemeetings", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.stderr.isEmpty ? r.stdout : r.stderr]) }
        let combined = r.stdout + "\n" + r.stderr
        if let match = combined.range(of: #"Token\s*:\s*([0-9]+)"#, options: .regularExpression) {
            let text = String(combined[match])
            let parsed = text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if !parsed.isEmpty { token = parsed; enabledByUs = true }
        }
        guard token != nil else { throw failure("PF did not provide an ownership token; refusing to install rules.") }
        try armCrashGuard()
    }

    func apply(_ rules: String) throws {
        try ensureEnabled()
        let r = shell("/sbin/pfctl", ["-a", anchor, "-f", "-"], input: rules)
        guard r.status == 0 else { throw NSError(domain: "ihatemeetings", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.stderr.isEmpty ? r.stdout : r.stderr]) }
        let verify = shell("/sbin/pfctl", ["-a", anchor, "-sr"])
        guard verify.status == 0 && !verify.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "ihatemeetings", code: 3, userInfo: [NSLocalizedDescriptionKey: "pf accepted the command but the ihatemeetings anchor did not contain the expected block rules."])
        }
    }

    func clear() throws {
        guard token != nil || guardFlag != nil else { return }
        let r = shell("/sbin/pfctl", ["-a", anchor, "-F", "rules"])
        guard r.status == 0 else { throw failure("Could not restore PF rules: " + r.stderr) }
    }

    func restore() throws {
        try clear()
        if enabledByUs, let token = token, !token.isEmpty {
            let r = shell("/sbin/pfctl", ["-X", token])
            guard r.status == 0 else { throw failure("Could not release PF ownership: " + r.stderr) }
        }
        disarmCrashGuard()
        self.token = nil
        enabledByUs = false
    }
}

final class AdapterGuard {
    private var flagPath: String?
    func arm(interface: String) throws {
        if flagPath != nil { return }
        let flag = try guardFile()
        flagPath = flag
        let parent = getpid()
        let script = "while kill -0 \(parent) 2>/dev/null; do sleep 1; done; if [ -f \(shQuote(flag)) ]; then /sbin/ifconfig \(shQuote(interface)) up >/dev/null 2>&1; rm -f \(shQuote(flag)); fi"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try p.run()
    }
    func disarm() {
        if let flagPath = flagPath { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: flagPath).deletingLastPathComponent().path) }
        flagPath = nil
    }
}

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var callback: (() -> Void)?
    private let signature: OSType = 0x4E545447 // NTTG

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let me = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            me.callback?()
            return noErr
        }, 1, &spec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &handlerRef)
    }

    deinit {
        if let hotKeyRef = hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef = handlerRef { RemoveEventHandler(handlerRef) }
    }

    func register(index: Int, callback: @escaping () -> Void) -> Bool {
        if let hotKeyRef = hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        self.callback = callback
        let options: [(UInt32, UInt32)] = [
            (UInt32(kVK_F6), 0),
            (UInt32(kVK_F6), UInt32(controlKey)),
            (UInt32(kVK_F6), UInt32(optionKey)),
            (UInt32(kVK_F6), UInt32(controlKey | optionKey)),
            (UInt32(kVK_F7), 0)
        ]
        let choice = options[max(0, min(index, options.count - 1))]
        var hk: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: 1)
        if RegisterEventHotKey(choice.0, choice.1, id, GetApplicationEventTarget(), 0, &hk) == noErr { hotKeyRef = hk; return true }; return false
    }
}

final class NetworkEngine {
    let pf = PFController()
    let guardHelper = AdapterGuard()
    private(set) var adapterWasDown = false
    private(set) var currentInterface = ""

    func setFast(interface: String, blocked: Bool) throws {
        currentInterface = interface
        if blocked {
            let rules = "block drop quick on \(interface) all\n"
            try pf.apply(rules)
            for address in interfaceAddresses(interface) { try killStates(address, nil) }
        } else { try pf.clear() }
    }

    func setAdapter(interface: String, down: Bool) throws {
        currentInterface = interface
        if down {
            let original = shell("/sbin/ifconfig", [interface])
            guard original.status == 0 && original.stdout.split(separator: "\n").first?.contains("<UP,") == true else { throw failure("The adapter must be enabled before starting.") }
            try guardHelper.arm(interface: interface)
            adapterWasDown = true
            let r = shell("/sbin/ifconfig", [interface, "down"])
            guard r.status == 0 else { throw NSError(domain: "ihatemeetings", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.stderr]) }
            adapterWasDown = true
        } else {
            let r = shell("/sbin/ifconfig", [interface, "up"])
            guard r.status == 0 else { throw NSError(domain: "ihatemeetings", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.stderr]) }
            adapterWasDown = false
            guardHelper.disarm()
        }
    }

    struct ZoomConnection: Hashable {
        let proto: String
        let localHost: String
        let localPort: Int
        let remoteHost: String
        let remotePort: Int
    }

    func zoomPIDs() -> [Int] {
        let r = shell("/usr/bin/pgrep", ["-if", "(/Zoom.app/|zoom.us|CptHost|Zoom Workplace)"])
        return r.stdout.split(whereSeparator: { $0 == "\n" || $0 == " " }).compactMap { Int($0) }
    }

    private func hostPort(_ text: String) -> (String, Int)? {
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            let host = String(text[text.index(after: text.startIndex)..<close])
            let after = text.index(after: close)
            guard after < text.endIndex, text[after] == ":", let port = Int(text[text.index(after: after)...]), (1...65535).contains(port) else { return nil }
            return (host, port)
        }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let host = String(text[..<colon])
        guard !host.isEmpty, host != "*", let port = Int(text[text.index(after: colon)...]), (1...65535).contains(port) else { return nil }
        return (host, port)
    }

    func zoomConnections() -> Set<ZoomConnection> {
        var result = Set<ZoomConnection>()
        for pid in zoomPIDs() {
            let r = shell("/usr/sbin/lsof", ["-nP", "-a", "-p", String(pid), "-iTCP", "-iUDP", "-FfPn"])
            var proto = ""
            for lineSub in r.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(lineSub)
                guard let tag = line.first else { continue }
                let value = String(line.dropFirst())
                if tag == "f" { proto = ""; continue }
                if tag == "P" {
                    let p = value.lowercased()
                    proto = (p == "tcp" || p == "udp") ? p : ""
                    continue
                }
                guard tag == "n", !proto.isEmpty, let arrow = value.range(of: "->") else { continue }
                let localText = String(value[..<arrow.lowerBound])
                let remoteText = String(value[arrow.upperBound...])
                guard let local = hostPort(localText), let remote = hostPort(remoteText) else { continue }
                result.insert(ZoomConnection(proto: proto, localHost: local.0, localPort: local.1, remoteHost: remote.0, remotePort: remote.1))
            }
        }
        return result
    }

    func applyZoomBlock(interface: String) throws -> Int {
        let connections = zoomConnections()
        guard !connections.isEmpty else { try pf.clear(); return 0 }
        var rules = ""
        for c in connections.sorted(by: { ($0.proto, $0.localHost, $0.localPort, $0.remoteHost, $0.remotePort) < ($1.proto, $1.localHost, $1.localPort, $1.remoteHost, $1.remotePort) }) {
            let family = (c.localHost.contains(":") || c.remoteHost.contains(":")) ? "inet6" : "inet"
            rules += "block drop quick on \(interface) \(family) proto \(c.proto) from \(c.localHost) port = \(c.localPort) to \(c.remoteHost) port = \(c.remotePort)\n"
            rules += "block drop quick on \(interface) \(family) proto \(c.proto) from \(c.remoteHost) port = \(c.remotePort) to \(c.localHost) port = \(c.localPort)\n"
        }
        try pf.apply(rules)
        for c in connections { try killStates(c.localHost, c.remoteHost) }
        return connections.count
    }

    func interfaceAddresses(_ interface: String) -> [String] {
        shell("/sbin/ifconfig", [interface]).stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count > 1 && (parts[0] == "inet" || parts[0] == "inet6") else { return nil }
            return String(parts[1])
        }
    }
    func killStates(_ local: String, _ remote: String?) throws {
        for reverse in [false, true] {
            let all = local.contains(":") ? "::/0" : "0.0.0.0/0"
            let args = reverse ? ["-k", remote ?? all, "-k", local] : ["-k", local, "-k", remote ?? all]
            let r = shell("/sbin/pfctl", args)
            guard r.status == 0 else { throw failure("PF state refresh failed: " + r.stderr) }
        }
    }
    func setMeet(interface: String, blocked: Bool) throws {
        if !blocked { try pf.clear(); return }
        try pf.apply(meetRules(interface: interface))
        for address in interfaceAddresses(interface) {
            for range in meetRanges where address.contains(":") == range.contains(":") { try killStates(address, range) }
        }
    }

    func restore() throws {
        if adapterWasDown && !currentInterface.isEmpty { try setAdapter(interface: currentInterface, down: false) }
        guardHelper.disarm()
        try pf.restore()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let adapterBox = NSPopUpButton(), modeBox = NSPopUpButton(), behaviorBox = NSPopUpButton(), hotKeyBox = NSPopUpButton()
    private let offField = NSTextField(string: "500"), onField = NSTextField(string: "500")
    private let offMax = NSTextField(string: "1000"), onMax = NSTextField(string: "1000")
    private let countField = NSTextField(string: "10"), limitField = NSTextField(string: "0")
    private let randomCheck = NSButton(checkboxWithTitle: "Random ranges", target: nil, action: nil)
    private let unlimitedCheck = NSButton(checkboxWithTitle: "Until stopped", target: nil, action: nil)
    private let startButton = NSButton(title: "Start", target: nil, action: nil)
    private let stopButton = NSButton(title: "Restore", target: nil, action: nil)
    private let testButton = NSButton(title: "Test", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let engine = NetworkEngine(), hotkeys = HotKeyManager()
    private var adapters: [AdapterInfo] = []
    private var running = false, closing = false, recoveryFailed = false
    private var stopFlag = false
    private let lock = NSLock()
    private let prefs = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildUI(); refreshAdapters(); loadSettings(); updateModeUI(); hotkeyChanged()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if running { closing = true; requestStop(); return .terminateLater }
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    @discardableResult private func label(_ title: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat) -> NSTextField {
        let v = NSTextField(labelWithString: title); place(v, x, y, width, 18); return v
    }
    private func place(_ v: NSView, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat = 24) {
        v.frame = NSRect(x: x, y: y, width: width, height: height); window.contentView?.addSubview(v)
        if let c = v as? NSControl { c.font = NSFont.systemFont(ofSize: 12) }
    }
    private func buildUI() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 350), styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "ihatemeetings 1.4"; window.center(); window.delegate = self
        place(adapterBox, 12, 313, 286); place(refreshButton, 301, 313, 78)
        refreshButton.target = self; refreshButton.action = #selector(refreshClicked)
        place(modeBox, 12, 283, 366)
        modeBox.addItems(withTitles: ["Fast — adapter traffic", "Adapter — disable / enable", "Zoom Lag — connection bursts", "Zoom Kick — hold connections blocked", "Meet Lag — media bursts", "Meet Disconnect — hold media blocked"])
        modeBox.target = self; modeBox.action = #selector(modeChanged)
        place(behaviorBox, 12, 253, 366)
        behaviorBox.addItems(withTitles: ["Automatic — repeat OFF / ON", "Manual — hotkey toggles OFF / ON"])
        behaviorBox.target = self; behaviorBox.action = #selector(modeChanged)
        place(randomCheck, 12, 227, 150); randomCheck.target = self; randomCheck.action = #selector(modeChanged)
        label("Min / fixed (ms)", 171, 230, 104); label("Max (ms)", 291, 230, 85)
        label("Offline", 12, 203, 100); place(offField, 171, 198, 99); place(offMax, 283, 198, 95)
        label("Online", 12, 174, 100); place(onField, 171, 169, 99); place(onMax, 283, 169, 95)
        label("Cycles", 12, 145, 48); place(countField, 63, 141, 65); place(unlimitedCheck, 143, 141, 122)
        unlimitedCheck.target = self; unlimitedCheck.action = #selector(modeChanged)
        label("Limit s", 268, 145, 49); place(limitField, 319, 141, 59)
        label("Hotkey", 12, 115, 47); place(hotKeyBox, 63, 110, 231); place(testButton, 300, 110, 78)
        hotKeyBox.addItems(withTitles: ["F6", "Control+F6", "Option+F6", "Control+Option+F6", "F7"])
        hotKeyBox.target = self; hotKeyBox.action = #selector(hotkeyChanged)
        testButton.target = self; testButton.action = #selector(testClicked)
        place(startButton, 12, 76, 179, 30); place(stopButton, 199, 76, 179, 30)
        startButton.target = self; startButton.action = #selector(startClicked)
        stopButton.target = self; stopButton.action = #selector(stopClicked); stopButton.isEnabled = false
        place(statusLabel, 12, 49, 366, 21); place(detailLabel, 12, 8, 366, 38)
        detailLabel.textColor = .secondaryLabelColor; detailLabel.font = NSFont.systemFont(ofSize: 11)
    }
    private func loadSettings() {
        for (key, field) in [("off",offField),("on",onField),("offMax",offMax),("onMax",onMax),("count",countField),("limit",limitField)] {
            if let value = prefs.string(forKey: key) { field.stringValue = value }
        }
        randomCheck.state = prefs.bool(forKey: "random") ? .on : .off
        unlimitedCheck.state = prefs.bool(forKey: "unlimited") ? .on : .off
        for (key, box) in [("mode",modeBox),("behavior",behaviorBox),("hotkey",hotKeyBox)] {
            box.selectItem(at: max(0,min(prefs.integer(forKey: key), box.numberOfItems-1)))
        }
        if let device = prefs.string(forKey: "adapter"), let i = adapters.firstIndex(where: { $0.device == device }) { adapterBox.selectItem(at: i) }
    }
    private func saveSettings() {
        for (key, field) in [("off",offField),("on",onField),("offMax",offMax),("onMax",onMax),("count",countField),("limit",limitField)] { prefs.set(field.stringValue, forKey: key) }
        prefs.set(randomCheck.state == .on, forKey: "random"); prefs.set(unlimitedCheck.state == .on, forKey: "unlimited")
        for (key, box) in [("mode",modeBox),("behavior",behaviorBox),("hotkey",hotKeyBox)] { prefs.set(box.indexOfSelectedItem, forKey: key) }
        prefs.set(selectedAdapter(), forKey: "adapter")
    }
    @objc private func refreshClicked() { if !running { refreshAdapters() } }
    private func refreshAdapters() {
        let previous = selectedAdapter()
        let r = shell("/usr/sbin/networksetup", ["-listallhardwareports"])
        var found: [AdapterInfo] = []; var port = ""
        for raw in r.stdout.split(separator: "\n") {
            let line = String(raw)
            if line.hasPrefix("Hardware Port: ") { port = String(line.dropFirst(15)) }
            if line.hasPrefix("Device: ") {
                let device = String(line.dropFirst(8)); let low = port.lowercased()
                if low.contains("wi-fi") || low.contains("ethernet") || low.contains("usb") || low.contains("thunderbolt") {
                    if device.range(of: #"^[a-zA-Z][a-zA-Z0-9]*$"#, options: .regularExpression) != nil { found.append(AdapterInfo(label: "\(port) (\(device))", device: device)) }
                }
            }
        }
        adapters = found; adapterBox.removeAllItems(); adapterBox.addItems(withTitles: found.map(\.label))
        let route = shell("/sbin/route", ["-n", "get", "default"]).stdout
        let active = route.split(separator: "\n").first { $0.contains("interface:") }?.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
        if let i = found.firstIndex(where: { $0.device == (previous ?? active ?? "") }) { adapterBox.selectItem(at: i) }
        if found.isEmpty { statusLabel.stringValue = "No Ethernet / Wi-Fi adapter found" }
    }
    @objc private func modeChanged() { updateModeUI() }
    private func updateModeUI() {
        guard !running else { return }
        let mode = NTMode(rawValue: modeBox.indexOfSelectedItem) ?? .fast
        let appMode = mode.rawValue >= 2
        let timed = mode == .zoomLag || mode == .meetLag || (!appMode && behaviorBox.indexOfSelectedItem == 0)
        behaviorBox.isEnabled = !appMode
        for c in [offField,onField,limitField] { c.isEnabled = timed }
        randomCheck.isEnabled = timed; unlimitedCheck.isEnabled = timed
        countField.isEnabled = timed && unlimitedCheck.state != .on
        offMax.isEnabled = timed && randomCheck.state == .on; onMax.isEnabled = offMax.isEnabled
        startButton.title = timed ? "Start" : "Switch OFF"
        startButton.isEnabled = !recoveryFailed
        if mode == .meetLag || mode == .meetHold { detailLabel.stringValue = "Meet media addresses, all apps on this adapter. May remain joined; does not guarantee a kick." }
        else if appMode { detailLabel.stringValue = "Detected Zoom connections on this adapter. Address-pair state refresh can affect other traffic to the same host." }
        else { detailLabel.stringValue = "A hotkey press starts / stops. Limit 0 = none. Adapter reconnects can take seconds." }
    }
    @objc private func hotkeyChanged() {
        if !hotkeys.register(index: hotKeyBox.indexOfSelectedItem, callback: { [weak self] in DispatchQueue.main.async { self?.toggleFromHotkey() } }) { showError("Hotkey unavailable. Choose another binding; use Restore to stop.") }
    }
    private func toggleFromHotkey() { running ? requestStop() : startRun(testOnly: false) }
    @objc private func startClicked() { toggleFromHotkey() }
    @objc private func stopClicked() { requestStop() }
    @objc private func testClicked() { startRun(testOnly: true) }
    private func selectedAdapter() -> String? {
        let i = adapterBox.indexOfSelectedItem; return adapters.indices.contains(i) ? adapters[i].device : nil
    }
    private func startRun(testOnly: Bool) {
        guard !running && !recoveryFailed else { return }
        guard let iface = selectedAdapter() else { showError("Select an adapter first."); return }
        let mode = NTMode(rawValue: modeBox.indexOfSelectedItem) ?? .fast
        let manual = mode == .zoomKick || mode == .meetHold || (mode.rawValue < 2 && behaviorBox.indexOfSelectedItem == 1)
        let needsTiming = !manual && !testOnly
        let timing = Timing(off: Int(offField.stringValue) ?? 0, offMax: Int(offMax.stringValue) ?? 0, on: Int(onField.stringValue) ?? 0, onMax: Int(onMax.stringValue) ?? 0, random: randomCheck.state == .on)
        let count = UInt64(countField.stringValue) ?? 0, limit = UInt64(limitField.stringValue) ?? UInt64.max
        let unlimited = unlimitedCheck.state == .on
        if needsTiming && (timing == nil || (!unlimited && !(1...1_000_000_000).contains(count)) || limit > 604800) {
            showError("Timing: 10–86400000 ms; Max must be at least Min. Cycles: 1–1000000000, or Until stopped. Limit: 0–604800 seconds."); return
        }
        saveSettings(); lock.lock(); stopFlag = false; lock.unlock()
        running = true; setRunningUI(true); statusLabel.stringValue = "Starting…"
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var message: String?; var restoreFailed = false; var cycles: UInt64 = 0
            let start = ProcessInfo.processInfo.systemUptime
            let deadline = needsTiming && limit > 0 ? start + Double(limit) : Double.greatestFiniteMagnitude
            func done() -> Bool { self.shouldStop() || ProcessInfo.processInfo.systemUptime >= deadline }
            do {
                if testOnly {
                    try self.setState(mode: mode, iface: iface, blocked: true)
                    self.sleepCancelable(750, deadline: deadline)
                    try self.setState(mode: mode, iface: iface, blocked: false)
                } else if manual {
                    try self.setState(mode: mode, iface: iface, blocked: true)
                    while !done() {
                        self.sleepCancelable(700, deadline: deadline)
                        if mode == .zoomKick && !done() { try self.setState(mode: mode, iface: iface, blocked: true) }
                    }
                } else if let timing = timing {
                    while !done() && (unlimited || cycles < count) {
                        try self.setState(mode: mode, iface: iface, blocked: true)
                        self.sleepCancelable(timing.duration(blocked: true), deadline: deadline)
                        if done() { break }
                        try self.setState(mode: mode, iface: iface, blocked: false); cycles += 1
                        self.sleepCancelable(timing.duration(blocked: false), deadline: deadline)
                    }
                }
            } catch { message = error.localizedDescription }
            do { try self.engine.restore() } catch { restoreFailed = true; message = (message ?? "") + "\nRestoration failed: " + error.localizedDescription }
            let finalMessage = message, failed = restoreFailed, completed = cycles, canceled = self.shouldStop()
            DispatchQueue.main.async {
                self.running = false; self.recoveryFailed = failed; self.setRunningUI(false); self.updateModeUI()
                self.statusLabel.stringValue = failed ? "Restoration failed — quit to retry" : testOnly ? (canceled ? "Test canceled — restored" : "API check complete — restored") : "Restored • \(completed) cycles"
                if let message = finalMessage { self.showError(message) }
                if self.closing { NSApp.reply(toApplicationShouldTerminate: !failed); self.closing = false }
            }
        }
    }
    private func setState(mode: NTMode, iface: String, blocked: Bool) throws {
        if blocked && shouldStop() { return }
        switch mode {
        case .fast: try engine.setFast(interface: iface, blocked: blocked)
        case .adapter: try engine.setAdapter(interface: iface, down: blocked)
        case .zoomLag,.zoomKick:
            if blocked {
                let n = try engine.applyZoomBlock(interface: iface)
                guard n > 0 else { throw failure("No active Zoom connections found. Join a test call and retry.") }
            } else { try engine.pf.clear() }
        case .meetLag,.meetHold: try engine.setMeet(interface: iface, blocked: blocked)
        }
        DispatchQueue.main.async { self.statusLabel.stringValue = blocked ? "OFF / blocked" : "ON / allowed" }
    }
    private func sleepCancelable(_ ms: Int, deadline: Double) {
        let end = min(ProcessInfo.processInfo.systemUptime + Double(ms)/1000, deadline)
        while !shouldStop() {
            let remaining = end - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { break }; usleep(useconds_t(min(remaining,0.05)*1_000_000))
        }
    }
    private func shouldStop() -> Bool { lock.lock(); defer { lock.unlock() }; return stopFlag }
    private func requestStop() { lock.lock(); stopFlag = true; lock.unlock(); statusLabel.stringValue = "Restoring…" }
    private func setRunningUI(_ on: Bool) {
        for c in [adapterBox,modeBox,behaviorBox,hotKeyBox] { c.isEnabled = !on }
        for c in [offField,onField,offMax,onMax,countField,limitField] { c.isEnabled = !on }
        for c in [randomCheck,unlimitedCheck,testButton,refreshButton] { c.isEnabled = !on }
        stopButton.isEnabled = on; startButton.title = on ? "Restore" : "Start"
    }
    private func showError(_ message: String) { let a = NSAlert(); a.messageText = "ihatemeetings"; a.informativeText = message; a.alertStyle = .warning; a.runModal() }
}

ensureElevated()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
