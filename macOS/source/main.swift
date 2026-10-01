import AppKit
import Carbon
import Foundation
import Darwin

enum NTMode: Int {
    case fast = 0
    case adapter = 1
    case zoomLag = 2
    case zoomKick = 3
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
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    if let input = input {
        let pipe = Pipe()
        p.standardInput = pipe
        do { try p.run() } catch { return ShellResult(status: 127, stdout: "", stderr: String(describing: error)) }
        pipe.fileHandleForWriting.write(input.data(using: .utf8) ?? Data())
        try? pipe.fileHandleForWriting.close()
    } else {
        do { try p.run() } catch { return ShellResult(status: 127, stdout: "", stderr: String(describing: error)) }
    }
    p.waitUntilExit()
    let so = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let se = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return ShellResult(status: p.terminationStatus, stdout: so, stderr: se)
}

func shQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func appleQuote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

func ensureElevated() {
    if geteuid() == 0 { return }
    if CommandLine.arguments.contains("--elevated") { fputs("NetToggle requires administrator privileges.\n", stderr); exit(1) }
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
    let command = "/bin/sh -c " + shQuote("exec " + shQuote(exe) + " --elevated >/tmp/nettoggle-macos.log 2>&1 </dev/null &")
    let script = "do shell script " + appleQuote(command) + " with administrator privileges"
    _ = shell("/usr/bin/osascript", ["-e", script])
    exit(0)
}

final class PFController {
    private let anchor = "com.apple/nettoggle"
    private var token: String?
    private var enabledByUs = false
    private var guardFlag: String?

    private func armCrashGuard() {
        if guardFlag != nil { return }
        let flag = "/tmp/nettoggle-pf-\(getpid()).guard"
        FileManager.default.createFile(atPath: flag, contents: Data())
        guardFlag = flag
        let parent = getpid()
        var cleanup = "/sbin/pfctl -a \(shQuote(anchor)) -F all >/dev/null 2>&1"
        if enabledByUs, let token = token, !token.isEmpty { cleanup += "; /sbin/pfctl -X \(shQuote(token)) >/dev/null 2>&1" }
        cleanup += "; rm -f \(shQuote(flag))"
        let script = "while kill -0 \(parent) 2>/dev/null; do sleep 1; done; if [ -f \(shQuote(flag)) ]; then \(cleanup); fi"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
    }

    private func disarmCrashGuard() {
        if let flag = guardFlag { try? FileManager.default.removeItem(atPath: flag) }
        guardFlag = nil
    }

    func ensureEnabled() throws {
        if token != nil || guardFlag != nil { return }
        let r = shell("/sbin/pfctl", ["-E"])
        guard r.status == 0 else { throw NSError(domain: "NetToggle", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.stderr.isEmpty ? r.stdout : r.stderr]) }
        let combined = r.stdout + "\n" + r.stderr
        if let match = combined.range(of: #"Token\s*:\s*([0-9]+)"#, options: .regularExpression) {
            let text = String(combined[match])
            let parsed = text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if !parsed.isEmpty { token = parsed; enabledByUs = true }
        }
        armCrashGuard()
    }

    func apply(_ rules: String) throws {
        try ensureEnabled()
        let r = shell("/sbin/pfctl", ["-a", anchor, "-f", "-"], input: rules)
        guard r.status == 0 else { throw NSError(domain: "NetToggle", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.stderr.isEmpty ? r.stdout : r.stderr]) }
        let verify = shell("/sbin/pfctl", ["-a", anchor, "-sr"])
        guard verify.status == 0 && !verify.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "NetToggle", code: 3, userInfo: [NSLocalizedDescriptionKey: "pf accepted the command but the NetToggle anchor did not contain the expected block rules."])
        }
    }

    func clear() {
        _ = shell("/sbin/pfctl", ["-a", anchor, "-F", "all"])
    }

    func restore() {
        clear()
        if enabledByUs, let token = token, !token.isEmpty { _ = shell("/sbin/pfctl", ["-X", token]) }
        disarmCrashGuard()
        self.token = nil
        enabledByUs = false
    }
}

final class AdapterGuard {
    private var flagPath: String?
    func arm(interface: String) {
        if flagPath != nil { return }
        let flag = "/tmp/nettoggle-adapter-\(getpid()).guard"
        FileManager.default.createFile(atPath: flag, contents: Data())
        flagPath = flag
        let parent = getpid()
        let script = "while kill -0 \(parent) 2>/dev/null; do sleep 1; done; if [ -f \(shQuote(flag)) ]; then /sbin/ifconfig \(shQuote(interface)) up >/dev/null 2>&1; rm -f \(shQuote(flag)); fi"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
    }
    func disarm() {
        if let flagPath = flagPath { try? FileManager.default.removeItem(atPath: flagPath) }
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

    func register(index: Int, callback: @escaping () -> Void) {
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
        if RegisterEventHotKey(choice.0, choice.1, id, GetApplicationEventTarget(), 0, &hk) == noErr { hotKeyRef = hk }
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
        } else { pf.clear() }
    }

    func setAdapter(interface: String, down: Bool) throws {
        currentInterface = interface
        if down {
            guardHelper.arm(interface: interface)
            let r = shell("/sbin/ifconfig", [interface, "down"])
            guard r.status == 0 else { throw NSError(domain: "NetToggle", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.stderr]) }
            adapterWasDown = true
        } else {
            let r = shell("/sbin/ifconfig", [interface, "up"])
            guard r.status == 0 else { throw NSError(domain: "NetToggle", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.stderr]) }
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
        guard !connections.isEmpty else { pf.clear(); return 0 }
        var rules = ""
        for c in connections.sorted(by: { ($0.proto, $0.localHost, $0.localPort, $0.remoteHost, $0.remotePort) < ($1.proto, $1.localHost, $1.localPort, $1.remoteHost, $1.remotePort) }) {
            let family = (c.localHost.contains(":") || c.remoteHost.contains(":")) ? "inet6" : "inet"
            rules += "block drop quick on \(interface) \(family) proto \(c.proto) from \(c.localHost) port = \(c.localPort) to \(c.remoteHost) port = \(c.remotePort)\n"
            rules += "block drop quick on \(interface) \(family) proto \(c.proto) from \(c.remoteHost) port = \(c.remotePort) to \(c.localHost) port = \(c.localPort)\n"
        }
        try pf.apply(rules)
        return connections.count
    }

    func restore() {
        if adapterWasDown && !currentInterface.isEmpty { _ = try? setAdapter(interface: currentInterface, down: false) }
        guardHelper.disarm()
        pf.restore()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let adapterBox = NSPopUpButton()
    private let modeBox = NSPopUpButton()
    private let behaviorBox = NSPopUpButton()
    private let offField = NSTextField(string: "500")
    private let onField = NSTextField(string: "500")
    private let countField = NSTextField(string: "10")
    private let unlimitedCheck = NSButton(checkboxWithTitle: "Until stopped", target: nil, action: nil)
    private let hotKeyBox = NSPopUpButton()
    private let startButton = NSButton(title: "Start", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop / restore", target: nil, action: nil)
    private let testButton = NSButton(title: "Test", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let detailLabel = NSTextField(labelWithString: "F6 toggles start / stop")
    private let engine = NetworkEngine()
    private let hotkeys = HotKeyManager()
    private var adapters: [AdapterInfo] = []
    private var running = false
    private var stopFlag = false
    private let lock = NSLock()
    private var cycles: UInt64 = 0
    private var switches: UInt64 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildUI()
        refreshAdapters()
        hotkeys.register(index: 0) { [weak self] in DispatchQueue.main.async { self?.toggleFromHotkey() } }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) { stopFlag = true; engine.restore() }
    func windowWillClose(_ notification: Notification) { stopFlag = true; engine.restore(); NSApp.terminate(nil) }

    private func addLabel(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let v = NSTextField(labelWithString: title); v.frame = NSRect(x: x, y: y, width: width, height: 18); window.contentView?.addSubview(v); return v
    }

    private func buildUI() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 430), styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "NetToggle 1.3"
        window.center(); window.delegate = self
        guard let c = window.contentView else { return }
        addLabel("Network adapter", x: 18, y: 392, width: 150)
        adapterBox.frame = NSRect(x: 18, y: 360, width: 300, height: 28); c.addSubview(adapterBox)
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshClicked)); refresh.frame = NSRect(x: 326, y: 360, width: 86, height: 28); c.addSubview(refresh)

        addLabel("Mode", x: 18, y: 330, width: 100)
        modeBox.frame = NSRect(x: 18, y: 300, width: 394, height: 28)
        modeBox.addItems(withTitles: ["Fast mode - block / allow adapter traffic","Adapter mode - disable / enable adapter","Zoom Lag - Zoom-only packet-loss bursts","Zoom Kick - block Zoom until restored"])
        modeBox.target = self; modeBox.action = #selector(modeChanged); c.addSubview(modeBox)

        behaviorBox.frame = NSRect(x: 18, y: 265, width: 394, height: 28)
        behaviorBox.addItems(withTitles: ["Automatic - repeat off / on cycles","Manual - hotkey toggles OFF / ON"]); behaviorBox.target = self; behaviorBox.action = #selector(modeChanged); c.addSubview(behaviorBox)

        addLabel("Offline / blocked (ms)", x: 18, y: 235, width: 150); offField.frame = NSRect(x: 170, y: 232, width: 74, height: 24); c.addSubview(offField)
        addLabel("Online / allowed (ms)", x: 255, y: 235, width: 130); onField.frame = NSRect(x: 340, y: 232, width: 72, height: 24); c.addSubview(onField)
        addLabel("Cycles", x: 18, y: 200, width: 60); countField.frame = NSRect(x: 80, y: 197, width: 70, height: 24); c.addSubview(countField)
        unlimitedCheck.frame = NSRect(x: 175, y: 198, width: 130, height: 24); c.addSubview(unlimitedCheck)

        addLabel("Hotkey", x: 18, y: 164, width: 60)
        hotKeyBox.frame = NSRect(x: 80, y: 157, width: 170, height: 28); hotKeyBox.addItems(withTitles: ["F6","Control+F6","Option+F6","Control+Option+F6","F7"]); hotKeyBox.target = self; hotKeyBox.action = #selector(hotkeyChanged); c.addSubview(hotKeyBox)
        testButton.target = self; testButton.action = #selector(testClicked); testButton.frame = NSRect(x: 326, y: 157, width: 86, height: 28); c.addSubview(testButton)

        startButton.target = self; startButton.action = #selector(startClicked); startButton.frame = NSRect(x: 18, y: 112, width: 190, height: 34); c.addSubview(startButton)
        stopButton.target = self; stopButton.action = #selector(stopClicked); stopButton.frame = NSRect(x: 222, y: 112, width: 190, height: 34); stopButton.isEnabled = false; c.addSubview(stopButton)
        statusLabel.frame = NSRect(x: 18, y: 70, width: 394, height: 22); c.addSubview(statusLabel)
        detailLabel.frame = NSRect(x: 18, y: 42, width: 394, height: 22); detailLabel.textColor = .secondaryLabelColor; c.addSubview(detailLabel)
        addLabel("Administrator permission is requested once per launch for pf/ifconfig.", x: 18, y: 14, width: 394)
        updateModeUI()
    }

    @objc private func refreshClicked() { refreshAdapters() }
    private func refreshAdapters() {
        let r = shell("/usr/sbin/networksetup", ["-listallhardwareports"])
        var found: [AdapterInfo] = []; var currentPort: String?
        for raw in r.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("Hardware Port: ") { currentPort = String(line.dropFirst("Hardware Port: ".count)) }
            else if line.hasPrefix("Device: "), let port = currentPort {
                let dev = String(line.dropFirst("Device: ".count))
                let low = port.lowercased()
                if low.contains("wi-fi") || low.contains("ethernet") || low.contains("usb") || low.contains("thunderbolt") { found.append(AdapterInfo(label: "\(port) (\(dev))", device: dev)) }
            }
        }
        adapters = found; adapterBox.removeAllItems(); adapterBox.addItems(withTitles: found.map(\.label))
        if found.isEmpty { statusLabel.stringValue = "No Ethernet/Wi-Fi interface found" }
    }

    @objc private func modeChanged() { updateModeUI() }
    private func updateModeUI() {
        let mode = NTMode(rawValue: modeBox.indexOfSelectedItem) ?? .fast
        let zoom = mode == .zoomLag || mode == .zoomKick
        adapterBox.isEnabled = true
        behaviorBox.isEnabled = !zoom
        let timed = mode != .zoomKick && !(mode != .zoomLag && behaviorBox.indexOfSelectedItem == 1)
        offField.isEnabled = timed; onField.isEnabled = timed; countField.isEnabled = timed; unlimitedCheck.isEnabled = timed
        if mode == .zoomLag { detailLabel.stringValue = "Zoom Lag alternates temporary Zoom-only blocks and allows." }
        else if mode == .zoomKick { detailLabel.stringValue = "Zoom Kick keeps only your local Zoom connections blocked until restored." }
        else { detailLabel.stringValue = "F6 toggles start / stop" }
        startButton.title = mode == .zoomKick ? "Disconnect Zoom" : mode == .zoomLag ? "Start Zoom Lag" : "Start"
    }

    @objc private func hotkeyChanged() { hotkeys.register(index: hotKeyBox.indexOfSelectedItem) { [weak self] in DispatchQueue.main.async { self?.toggleFromHotkey() } } }
    private func toggleFromHotkey() { running ? requestStop() : startRun(testOnly: false) }
    @objc private func startClicked() { startRun(testOnly: false) }
    @objc private func stopClicked() { requestStop() }
    @objc private func testClicked() { startRun(testOnly: true) }

    private func selectedAdapter() -> String? {
        let i = adapterBox.indexOfSelectedItem
        return (i >= 0 && i < adapters.count) ? adapters[i].device : nil
    }

    private func intField(_ field: NSTextField, min: Int, max: Int) -> Int? {
        guard let v = Int(field.stringValue), v >= min, v <= max else { return nil }; return v
    }

    private func startRun(testOnly: Bool) {
        if running { return }
        guard let iface = selectedAdapter() else { showError("Select a network adapter first."); return }
        let mode = NTMode(rawValue: modeBox.indexOfSelectedItem) ?? .fast
        let manual = mode == .zoomKick || (mode != .zoomLag && behaviorBox.indexOfSelectedItem == 1)
        let offMS = intField(offField, min: 10, max: 86_400_000) ?? 500
        let onMS = intField(onField, min: 10, max: 86_400_000) ?? 500
        let count = intField(countField, min: 1, max: 1_000_000_000) ?? 10
        let unlimited = unlimitedCheck.state == .on
        stopFlag = false; running = true; cycles = 0; switches = 0
        setRunningUI(true); statusLabel.stringValue = testOnly ? "Testing selected mode…" : "Starting…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var message: String? = nil
            do {
                if testOnly {
                    if mode == .zoomLag || mode == .zoomKick {
                        let n = try self.engine.applyZoomBlock(interface: iface)
                        if n == 0 { throw NSError(domain: "NetToggle", code: 2, userInfo: [NSLocalizedDescriptionKey: "No active Zoom network connections were detected. Join/start a Zoom call and test again."]) }
                        self.sleepCancelable(750)
                        self.engine.pf.clear()
                    } else {
                        try self.setState(mode: mode, iface: iface, blocked: true)
                        self.sleepCancelable(750)
                        try self.setState(mode: mode, iface: iface, blocked: false)
                    }
                } else if mode == .zoomKick {
                    while !self.shouldStop() {
                        let n = try self.engine.applyZoomBlock(interface: iface)
                        DispatchQueue.main.async { self.statusLabel.stringValue = n > 0 ? "Zoom network BLOCKED (\(n) connections)" : "Waiting for active Zoom traffic…" }
                        self.sleepCancelable(700)
                    }
                } else if manual {
                    try self.setState(mode: mode, iface: iface, blocked: true)
                    while !self.shouldStop() { self.sleepCancelable(200) }
                } else {
                    while !self.shouldStop() && (unlimited || self.cycles < UInt64(count)) {
                        try self.setState(mode: mode, iface: iface, blocked: true); self.switches += 1
                        self.sleepCancelable(testOnly ? 750 : offMS)
                        if self.shouldStop() { break }
                        try self.setState(mode: mode, iface: iface, blocked: false); self.switches += 1; self.cycles += 1
                        self.sleepCancelable(onMS)
                    }
                }
            } catch { message = error.localizedDescription }
            self.engine.restore()
            DispatchQueue.main.async {
                self.running = false; self.setRunningUI(false); self.updateModeUI()
                if let message = message { self.statusLabel.stringValue = "Stopped with an error"; self.showError(message) }
                else { self.statusLabel.stringValue = testOnly ? "Test passed - state changed and restored" : "Stopped - restored" }
            }
        }
    }

    private func setState(mode: NTMode, iface: String, blocked: Bool) throws {
        switch mode {
        case .fast: try engine.setFast(interface: iface, blocked: blocked)
        case .adapter: try engine.setAdapter(interface: iface, down: blocked)
        case .zoomLag, .zoomKick:
            if blocked {
                let n = try engine.applyZoomBlock(interface: iface)
                DispatchQueue.main.async { self.statusLabel.stringValue = n > 0 ? "Zoom network BLOCKED (\(n) connections)" : "Waiting for active Zoom traffic…" }
            } else { engine.pf.clear(); DispatchQueue.main.async { self.statusLabel.stringValue = "Zoom network ALLOWED" } }
        }
    }

    private func sleepCancelable(_ ms: Int) {
        var remaining = ms
        while remaining > 0 && !shouldStop() { let chunk = min(remaining, 100); usleep(useconds_t(chunk * 1000)); remaining -= chunk }
    }
    private func shouldStop() -> Bool { lock.lock(); defer { lock.unlock() }; return stopFlag }
    private func requestStop() { lock.lock(); stopFlag = true; lock.unlock(); statusLabel.stringValue = "Restoring…" }

    private func setRunningUI(_ on: Bool) {
        startButton.isEnabled = !on
        stopButton.isEnabled = on
        testButton.isEnabled = !on
        modeBox.isEnabled = !on
        behaviorBox.isEnabled = !on
        adapterBox.isEnabled = !on
        offField.isEnabled = !on; onField.isEnabled = !on; countField.isEnabled = !on; unlimitedCheck.isEnabled = !on
        if on { startButton.title = "Running" }
    }

    private func showError(_ message: String) {
        let a = NSAlert(); a.messageText = "NetToggle"; a.informativeText = message; a.alertStyle = .warning; a.runModal()
    }
}

ensureElevated()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
