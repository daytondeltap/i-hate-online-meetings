import AppKit
import Carbon
import Foundation
import Darwin

enum NTMode: Int { case fast = 0, adapter, zoomLag, zoomKick, meetLag, meetHold }
struct AdapterInfo { let label: String; let device: String }
struct ShellResult { let status: Int32; let stdout: String; let stderr: String }

@discardableResult
func shell(_ executable: String, _ args: [String], input: String? = nil) -> ShellResult {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("out"), errors = dir.appendingPathComponent("err"), stdin = dir.appendingPathComponent("in")
        try Data().write(to: output); try Data().write(to: errors); try (input ?? "").data(using: .utf8)!.write(to: stdin)
        let out = try FileHandle(forWritingTo: output), err = try FileHandle(forWritingTo: errors), inf = try FileHandle(forReadingFrom: stdin)
        defer { try? out.close(); try? err.close(); try? inf.close() }
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args; p.standardOutput = out; p.standardError = err; p.standardInput = inf
        try p.run(); p.waitUntilExit()
        return ShellResult(status: p.terminationStatus, stdout: (try? String(contentsOf: output, encoding: .utf8)) ?? "", stderr: (try? String(contentsOf: errors, encoding: .utf8)) ?? "")
    } catch { return ShellResult(status: 127, stdout: "", stderr: error.localizedDescription) }
}
func failure(_ message: String) -> NSError { NSError(domain: "ihatemeetings", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
func shQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func appleQuote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
func guardFile() throws -> String {
    var template = Array("/private/tmp/ihatemeetings.XXXXXX".utf8CString)
    guard let ptr = mkdtemp(&template) else { throw failure("Could not create recovery directory.") }
    let path = String(cString: ptr) + "/guard"; try Data().write(to: URL(fileURLWithPath: path)); return path
}
func ensureElevated() {
    if geteuid() == 0 { return }
    if CommandLine.arguments.contains("--elevated") { fputs("ihatemeetings requires administrator privileges.\n", stderr); exit(1) }
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
    let command = "/bin/sh -c " + shQuote("exec " + shQuote(exe) + " --elevated >/dev/null 2>&1 </dev/null &")
    _ = shell("/usr/bin/osascript", ["-e", "do shell script " + appleQuote(command) + " with administrator privileges"]); exit(0)
}

final class PFController {
    private let anchor = "com.apple/ihatemeetings-\(getpid())"
    private var token: String?; private var enabledByUs = false; private var guardFlag: String?
    private func armCrashGuard() throws {
        if guardFlag != nil { return }; let flag = try guardFile(); guardFlag = flag; let parent = getpid()
        var cleanup = "/sbin/pfctl -a \(shQuote(anchor)) -F all >/dev/null 2>&1"
        if enabledByUs, let token, !token.isEmpty { cleanup += "; /sbin/pfctl -X \(shQuote(token)) >/dev/null 2>&1" }
        cleanup += "; rm -f \(shQuote(flag)); rmdir \(shQuote(URL(fileURLWithPath: flag).deletingLastPathComponent().path))"
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", "while kill -0 \(parent) 2>/dev/null; do sleep 1; done; if [ -f \(shQuote(flag)) ]; then \(cleanup); fi"]; try p.run()
    }
    private func disarmCrashGuard() { if let flag = guardFlag { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: flag).deletingLastPathComponent().path) }; guardFlag = nil }
    func ensureEnabled() throws {
        if token != nil || guardFlag != nil { return }
        let root = shell("/sbin/pfctl", ["-sr"]); guard root.status == 0 && root.stdout.contains("anchor \"com.apple/*\"") else { throw failure("The active PF configuration does not invoke com.apple/* anchors.") }
        let r = shell("/sbin/pfctl", ["-E"]); guard r.status == 0 else { throw failure(r.stderr.isEmpty ? r.stdout : r.stderr) }
        let combined = r.stdout + "\n" + r.stderr
        if let m = combined.range(of: #"Token\s*:\s*([0-9]+)"#, options: .regularExpression) { let parsed = String(combined[m]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined(); if !parsed.isEmpty { token = parsed; enabledByUs = true } }
        guard token != nil else { throw failure("PF did not provide an ownership token.") }; try armCrashGuard()
    }
    func apply(_ rules: String) throws {
        try ensureEnabled(); let r = shell("/sbin/pfctl", ["-a", anchor, "-f", "-"], input: rules); guard r.status == 0 else { throw failure(r.stderr.isEmpty ? r.stdout : r.stderr) }
        let verify = shell("/sbin/pfctl", ["-a", anchor, "-sr"]); guard verify.status == 0 && !verify.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("PF accepted the command but no ihatemeetings rules were installed.") }
    }
    func clear() throws { guard token != nil || guardFlag != nil else { return }; let r = shell("/sbin/pfctl", ["-a", anchor, "-F", "rules"]); guard r.status == 0 else { throw failure("Could not restore PF rules: " + r.stderr) } }
    func restore() throws { try clear(); if enabledByUs, let token, !token.isEmpty { let r = shell("/sbin/pfctl", ["-X", token]); guard r.status == 0 else { throw failure("Could not release PF ownership: " + r.stderr) } }; disarmCrashGuard(); token = nil; enabledByUs = false }
}

final class AdapterGuard {
    private var flagPath: String?
    func arm(interface: String) throws { if flagPath != nil { return }; let flag = try guardFile(); flagPath = flag; let parent = getpid(); let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", "while kill -0 \(parent) 2>/dev/null; do sleep 1; done; if [ -f \(shQuote(flag)) ]; then /sbin/ifconfig \(shQuote(interface)) up >/dev/null 2>&1; rm -f \(shQuote(flag)); fi"]; try p.run() }
    func disarm() { if let flagPath { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: flagPath).deletingLastPathComponent().path) }; flagPath = nil }
}

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?; private var handlerRef: EventHandlerRef?; private var callback: (() -> Void)?; private let signature: OSType = 0x4E545447
    init() { var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)); InstallEventHandler(GetApplicationEventTarget(), { _,_,data in guard let data else { return noErr }; Unmanaged<HotKeyManager>.fromOpaque(data).takeUnretainedValue().callback?(); return noErr }, 1, &spec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &handlerRef) }
    deinit { if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }; if let handlerRef { RemoveEventHandler(handlerRef) } }
    func register(index: Int, callback: @escaping () -> Void) -> Bool { if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }; self.callback = callback; let o:[(UInt32,UInt32)] = [(UInt32(kVK_F6),0),(UInt32(kVK_F6),UInt32(controlKey)),(UInt32(kVK_F6),UInt32(optionKey)),(UInt32(kVK_F6),UInt32(controlKey|optionKey)),(UInt32(kVK_F7),0)]; let c=o[max(0,min(index,o.count-1))]; var hk:EventHotKeyRef?; let id=EventHotKeyID(signature:signature,id:1); if RegisterEventHotKey(c.0,c.1,id,GetApplicationEventTarget(),0,&hk) == noErr { hotKeyRef=hk; return true }; return false }
}

struct AdvancedPreset: Codable { var app = ""; var proto = 0; var direction = 0; var localPort = 0; var remote = ""; var remotePort = 0 }
func connections(for pids: Set<Int>) -> [Connection] {
    guard !pids.isEmpty else { return [] }
    // Inspect all socket owners so shared UDP bindings cannot be mistaken for one app.
    let r = shell("/usr/sbin/lsof", ["-nP", "-iTCP", "-iUDP", "-FpcPn"])
    guard r.status == 0 else { return [] }
    return parseOwnedConnections(r.stdout, selected: pids)
}
func ipMatches(_ address: String, cidr: String) -> Bool {
    cidr.isEmpty || IPNetwork(cidr)?.contains(address) == true
}

final class NetworkEngine {
    let pf=PFController(), guardHelper=AdapterGuard(); private(set)var adapterWasDown=false,currentInterface=""
    func setFast(interface:String,blocked:Bool)throws{currentInterface=interface;if blocked{try pf.apply("block drop quick on \(interface) all\n");for a in interfaceAddresses(interface){try killStates(a,nil)}}else{try pf.clear()}}
    func setAdapter(interface:String,down:Bool)throws{currentInterface=interface;if down{let o=shell("/sbin/ifconfig",[interface]);guard o.status == 0&&o.stdout.split(separator:"\n").first?.contains("<UP,") == true else{throw failure("The adapter must be enabled before starting.")};try guardHelper.arm(interface:interface);adapterWasDown=true;let r=shell("/sbin/ifconfig",[interface,"down"]);guard r.status == 0 else{throw failure(r.stderr)}}else{let r=shell("/sbin/ifconfig",[interface,"up"]);guard r.status == 0 else{throw failure(r.stderr)};adapterWasDown=false;guardHelper.disarm()}}
    func zoomPIDs()->Set<Int>{Set(shell("/usr/bin/pgrep",["-if","(/Zoom.app/|zoom.us|CptHost|Zoom Workplace)"]).stdout.split(whereSeparator:{$0 == "\n"||$0 == " "}).compactMap{Int($0)})}
    func pids(forExecutable path:String)->Set<Int>{var out=Set<Int>();for app in NSWorkspace.shared.runningApplications{if app.executableURL?.standardized.path.caseInsensitiveCompare(URL(fileURLWithPath:path).standardized.path) == .orderedSame{out.insert(Int(app.processIdentifier))}};return out}
    func zoomConnections()->[Connection]{connections(for:zoomPIDs())}
    func applyZoomBlock(interface:String)throws->Int{let c=zoomConnections().filter{!$0.remoteHost.isEmpty};guard !c.isEmpty else{try pf.clear();return 0};try applyExact(interface:interface,connections:c,direction:0);return c.count}
    func applyExact(interface:String,connections:[Connection],direction:Int)throws{var rules="";for c in connections{let fam=(c.localHost.contains(":")||c.remoteHost.contains(":")) ? "inet6":"inet";if direction != 2{rules += "block drop quick on \(interface) \(fam) proto \(c.proto) from \(c.localHost) port = \(c.localPort) to \(c.remoteHost) port = \(c.remotePort)\n"};if direction != 1{rules += "block drop quick on \(interface) \(fam) proto \(c.proto) from \(c.remoteHost) port = \(c.remotePort) to \(c.localHost) port = \(c.localPort)\n"}};guard !rules.isEmpty else{throw failure("No matching rules were generated.")};try pf.apply(rules);try killExactStates(connections)}
    func killExactStates(_ connections: [Connection]) throws {
        let states = shell("/sbin/pfctl", ["-ss", "-vv"])
        guard states.status == 0 else { throw failure("Could not inspect PF states: " + states.stderr) }
        for id in matchingStateIDs(states.stdout, connections: connections) {
            let result = shell("/sbin/pfctl", ["-k", "id", "-k", id])
            guard result.status == 0 else { throw failure("Could not clear the selected connection state: " + result.stderr) }
        }
    }
    func advancedConnections(_ preset:AdvancedPreset)->[Connection]{let pids=pids(forExecutable:preset.app);return connections(for:pids).filter{c in if c.remoteHost.isEmpty{return false};if preset.proto == 1 && c.proto != "tcp"{return false};if preset.proto == 2 && c.proto != "udp"{return false};if preset.localPort>0 && c.localPort != preset.localPort{return false};if preset.remotePort>0 && c.remotePort != preset.remotePort{return false};return ipMatches(c.remoteHost,cidr:preset.remote)}}
    func applyAdvanced(interface:String,preset:AdvancedPreset)throws->Int{guard !preset.app.isEmpty else{throw failure("Choose an application in Configure.")};guard FileManager.default.fileExists(atPath:preset.app) else{throw failure("Selected application executable was not found.")};let c=advancedConnections(preset);guard !c.isEmpty else{try pf.clear();return 0};try applyExact(interface:interface,connections:c,direction:preset.direction);return c.count}
    func interfaceAddresses(_ interface:String)->[String]{shell("/sbin/ifconfig",[interface]).stdout.split(separator:"\n").compactMap{let p=$0.split(whereSeparator:{$0.isWhitespace});guard p.count>1&&(p[0] == "inet"||p[0] == "inet6") else{return nil};return String(p[1])}}
    func killStates(_ local:String,_ remote:String?)throws{for reverse in [false,true]{let all=local.contains(":") ? "::/0":"0.0.0.0/0";let args=reverse ? ["-k",remote ?? all,"-k",local]:["-k",local,"-k",remote ?? all];let r=shell("/sbin/pfctl",args);guard r.status == 0 else{throw failure("PF state refresh failed: "+r.stderr)}}}
    func setMeet(interface:String,blocked:Bool)throws{if !blocked{try pf.clear();return};try pf.apply(meetRules(interface:interface));for a in interfaceAddresses(interface){for range in meetRanges where a.contains(":") == range.contains(":"){try killStates(a,range)}}}
    func restore()throws{if adapterWasDown && !currentInterface.isEmpty{try setAdapter(interface:currentInterface,down:false)};guardHelper.disarm();try pf.restore()}
}

final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    private var window:NSWindow!,editor:NSPanel?
    private let advancedCheck=NSButton(checkboxWithTitle:"Advanced mode",target:nil,action:nil),configureButton=NSButton(title:"Configure",target:nil,action:nil)
    private let adapterBox=NSPopUpButton(),modeBox=NSPopUpButton(),behaviorBox=NSPopUpButton(),hotKeyBox=NSPopUpButton()
    private let offField=NSTextField(string:"500"),onField=NSTextField(string:"500"),offMax=NSTextField(string:"1000"),onMax=NSTextField(string:"1000"),countField=NSTextField(string:"10"),limitField=NSTextField(string:"0")
    private let randomCheck=NSButton(checkboxWithTitle:"Random ranges",target:nil,action:nil),unlimitedCheck=NSButton(checkboxWithTitle:"Until stopped",target:nil,action:nil)
    private let startButton=NSButton(title:"Start",target:nil,action:nil),stopButton=NSButton(title:"Restore",target:nil,action:nil),testButton=NSButton(title:"Test",target:nil,action:nil),refreshButton=NSButton(title:"Refresh",target:nil,action:nil)
    private let statusLabel=NSTextField(labelWithString:"Ready"),detailLabel=NSTextField(wrappingLabelWithString:"")
    private let engine=NetworkEngine(),hotkeys=HotKeyManager();private var adapters:[AdapterInfo]=[];private var running=false,closing=false,recoveryFailed=false,stopFlag=false;private let lock=NSLock(),prefs=UserDefaults.standard
    private var presets=[AdvancedPreset](repeating:AdvancedPreset(),count:5),currentPreset=0,inspected:[Connection]=[],inspectedApp=""
    private var presetBox:NSPopUpButton?,appField:NSTextField?,protoBox:NSPopUpButton?,directionBox:NSPopUpButton?,localPortField:NSTextField?,remoteField:NSTextField?,remotePortField:NSTextField?,flowBox:NSPopUpButton?
    func applicationDidFinishLaunching(_ n:Notification){buildUI();refreshAdapters();loadSettings();updateModeUI();hotkeyChanged();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    func applicationShouldTerminate(_ s:NSApplication)->NSApplication.TerminateReply{if running{closing=true;requestStop();return .terminateLater};return .terminateNow}
    func windowShouldClose(_ sender:NSWindow)->Bool{if sender === editor{editorClose();return false};NSApp.terminate(nil);return false}
    @discardableResult private func label(_ t:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat)->NSTextField{let v=NSTextField(labelWithString:t);place(v,x,y,w,18);return v}
    private func place(_ v:NSView,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat=24,in host:NSView?=nil){v.frame=NSRect(x:x,y:y,width:w,height:h);(host ?? window.contentView)?.addSubview(v);if let c=v as? NSControl{c.font=NSFont.systemFont(ofSize:12)}}
    private func buildUI(){window=NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:500),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false);window.title="ihatemeetings 1.5.3";window.center();window.delegate=self
        place(advancedCheck,16,462,180);place(configureButton,404,456,100);advancedCheck.target=self;advancedCheck.action=#selector(modeChanged);configureButton.target=self;configureButton.action=#selector(openEditor)
        place(adapterBox,16,420,380);place(refreshButton,404,420,100);refreshButton.target=self;refreshButton.action=#selector(refreshClicked)
        place(modeBox,16,380,488);modeBox.addItems(withTitles:["Fast — adapter traffic","Adapter — disable / enable","Zoom Lag — connection bursts","Zoom Kick — hold connections blocked","Meet Lag — media bursts","Meet Disconnect — hold media blocked"]);modeBox.target=self;modeBox.action=#selector(modeChanged)
        place(behaviorBox,16,340,488);behaviorBox.addItems(withTitles:["Automatic — repeat OFF / ON","Manual — hotkey toggles OFF / ON"]);behaviorBox.target=self;behaviorBox.action=#selector(modeChanged)
        place(randomCheck,16,300,170);randomCheck.target=self;randomCheck.action=#selector(modeChanged);label("Min / fixed (ms)",200,303,130);label("Max (ms)",360,303,100)
        label("Offline",16,263,100);place(offField,200,258,140);place(offMax,360,258,144);label("Online",16,223,100);place(onField,200,218,140);place(onMax,360,218,144)
        label("Cycles",16,183,48);place(countField,70,178,90);place(unlimitedCheck,180,178,140);unlimitedCheck.target=self;unlimitedCheck.action=#selector(modeChanged);label("Limit s",340,183,62);place(limitField,410,178,94)
        label("Hotkey",16,143,47);place(hotKeyBox,70,138,320);place(testButton,404,138,100);hotKeyBox.addItems(withTitles:["F6","Control+F6","Option+F6","Control+Option+F6","F7"]);hotKeyBox.target=self;hotKeyBox.action=#selector(hotkeyChanged);testButton.target=self;testButton.action=#selector(testClicked)
        place(startButton,16,92,238,30);place(stopButton,266,92,238,30);startButton.target=self;startButton.action=#selector(startClicked);stopButton.target=self;stopButton.action=#selector(stopClicked);stopButton.isEnabled=false
        place(statusLabel,16,60,488,21);place(detailLabel,16,12,488,42);detailLabel.textColor = .secondaryLabelColor;detailLabel.font=NSFont.systemFont(ofSize:11);detailLabel.maximumNumberOfLines=2;detailLabel.lineBreakMode = .byTruncatingMiddle
    }
    private func loadPresets(){for i in 0..<5{if let d=prefs.data(forKey:"advanced.preset.\(i)"),let p=try? JSONDecoder().decode(AdvancedPreset.self,from:d){presets[i]=p}};currentPreset=max(0,min(4,prefs.integer(forKey:"advanced.current")))}
    private func savePreset(_ i:Int){guard presets.indices.contains(i),let d=try? JSONEncoder().encode(presets[i]) else{return};prefs.set(d,forKey:"advanced.preset.\(i)");prefs.set(i,forKey:"advanced.current")}
    private func loadSettings(){loadPresets();for(k,f) in [("off",offField),("on",onField),("offMax",offMax),("onMax",onMax),("count",countField),("limit",limitField)]{if let v=prefs.string(forKey:k){f.stringValue=v}};randomCheck.state=prefs.bool(forKey:"random") ? .on:.off;unlimitedCheck.state=prefs.bool(forKey:"unlimited") ? .on:.off;advancedCheck.state=prefs.bool(forKey:"advanced.enabled") ? .on:.off;for(k,b) in [("mode",modeBox),("behavior",behaviorBox),("hotkey",hotKeyBox)]{b.selectItem(at:max(0,min(prefs.integer(forKey:k),b.numberOfItems-1)))};if let d=prefs.string(forKey:"adapter"),let i=adapters.firstIndex(where:{$0.device == d}){adapterBox.selectItem(at:i)}}
    private func saveSettings(){for(k,f) in [("off",offField),("on",onField),("offMax",offMax),("onMax",onMax),("count",countField),("limit",limitField)]{prefs.set(f.stringValue,forKey:k)};prefs.set(randomCheck.state == .on,forKey:"random");prefs.set(unlimitedCheck.state == .on,forKey:"unlimited");prefs.set(advancedCheck.state == .on,forKey:"advanced.enabled");for(k,b) in [("mode",modeBox),("behavior",behaviorBox),("hotkey",hotKeyBox)]{prefs.set(b.indexOfSelectedItem,forKey:k)};prefs.set(selectedAdapter(),forKey:"adapter")}
    @objc private func refreshClicked(){if !running{refreshAdapters()}}
    private func refreshAdapters(){let prev=selectedAdapter();let r=shell("/usr/sbin/networksetup",["-listallhardwareports"]);var found:[AdapterInfo]=[],port="";for raw in r.stdout.split(separator:"\n"){let line=String(raw);if line.hasPrefix("Hardware Port: "){port=String(line.dropFirst(15))};if line.hasPrefix("Device: "){let d=String(line.dropFirst(8)),low=port.lowercased();if low.contains("wi-fi")||low.contains("ethernet")||low.contains("usb")||low.contains("thunderbolt"){if d.range(of:#"^[a-zA-Z][a-zA-Z0-9]*$"#,options:.regularExpression) != nil{found.append(AdapterInfo(label:"\(port) (\(d))",device:d))}}}};adapters=found;adapterBox.removeAllItems();adapterBox.addItems(withTitles:found.map(\.label));let route=shell("/sbin/route",["-n","get","default"]).stdout;let active=route.split(separator:"\n").first{$0.contains("interface:")}?.split(separator:":").last?.trimmingCharacters(in:.whitespaces);if let i=found.firstIndex(where:{$0.device == (prev ?? active ?? "")}){adapterBox.selectItem(at:i)};if found.isEmpty{statusLabel.stringValue="No Ethernet / Wi-Fi adapter found"}}
    @objc private func modeChanged(){saveSettings();updateModeUI()}
    private func updateModeUI(){guard !running else{return};let adv=advancedCheck.state == .on;let mode=NTMode(rawValue:modeBox.indexOfSelectedItem) ?? .fast;let appMode=mode.rawValue>=2;let timed=adv ? behaviorBox.indexOfSelectedItem == 0 : (mode == .zoomLag || mode == .meetLag || (!appMode && behaviorBox.indexOfSelectedItem == 0));modeBox.isEnabled = !adv;behaviorBox.isEnabled = adv || !appMode;adapterBox.isEnabled=true;refreshButton.isEnabled=true;configureButton.isEnabled=adv;for c in [offField,onField,limitField]{c.isEnabled=timed};randomCheck.isEnabled=timed;unlimitedCheck.isEnabled=timed;countField.isEnabled=timed && unlimitedCheck.state != .on;offMax.isEnabled=timed && randomCheck.state == .on;onMax.isEnabled=offMax.isEnabled;startButton.title=timed ? (adv ? "Start advanced":"Start") : "Switch OFF";startButton.isEnabled = !recoveryFailed;if adv{let p=presets[currentPreset];detailLabel.stringValue="Advanced preset \(currentPreset+1): "+(p.app.isEmpty ? "choose an application in Configure":p.app)}else if mode == .meetLag || mode == .meetHold{detailLabel.stringValue="Meet media addresses on this adapter; may remain joined."}else if appMode{detailLabel.stringValue="Detected Zoom connections on this adapter."}else{detailLabel.stringValue="A hotkey press starts / stops. Limit 0 = none."}}
    @objc private func hotkeyChanged(){if !hotkeys.register(index:hotKeyBox.indexOfSelectedItem,callback:{[weak self] in DispatchQueue.main.async{self?.toggleFromHotkey()}}){showError("Hotkey unavailable. Choose another binding.")}}
    private func toggleFromHotkey(){guard editor==nil else{return};running ? requestStop():startRun(testOnly:false)};@objc private func startClicked(){toggleFromHotkey()};@objc private func stopClicked(){requestStop()};@objc private func testClicked(){startRun(testOnly:true)}
    private func selectedAdapter()->String?{let i=adapterBox.indexOfSelectedItem;return adapters.indices.contains(i) ? adapters[i].device:nil}
    private func timingSettings(manual:Bool,testOnly:Bool)->(Timing?,UInt64,UInt64,Bool)?{let needs = !manual && !testOnly;let t=Timing(off:Int(offField.stringValue) ?? 0,offMax:Int(offMax.stringValue) ?? 0,on:Int(onField.stringValue) ?? 0,onMax:Int(onMax.stringValue) ?? 0,random:randomCheck.state == .on);let count=UInt64(countField.stringValue) ?? 0,limit=UInt64(limitField.stringValue) ?? UInt64.max,unlimited=unlimitedCheck.state == .on;if needs && (t == nil || (!unlimited && !(1...1_000_000_000).contains(count)) || limit>604800){showError("Timing: 10–86400000 ms; Max must be at least Min. Cycles: 1–1000000000, or Until stopped. Limit: 0–604800 seconds.");return nil};return(t,count,limit,unlimited)}
    private func startRun(testOnly:Bool){guard !running && !recoveryFailed && editor==nil else{return};guard let iface=selectedAdapter() else{showError("Select an adapter first.");return};let adv=advancedCheck.state == .on,mode=NTMode(rawValue:modeBox.indexOfSelectedItem) ?? .fast;let manual=adv ? behaviorBox.indexOfSelectedItem == 1 : (mode == .zoomKick || mode == .meetHold || (mode.rawValue<2 && behaviorBox.indexOfSelectedItem == 1));guard let(timing,count,limit,unlimited)=timingSettings(manual:manual,testOnly:testOnly) else{return};if adv{let p=presets[currentPreset];guard !p.app.isEmpty else{showError("Open Configure and choose an application for the selected preset.");return}};saveSettings();lock.lock();stopFlag=false;lock.unlock();running=true;setRunningUI(true);statusLabel.stringValue=testOnly ? "Testing…":"Starting…";let preset=presets[currentPreset]
        DispatchQueue.global(qos:.userInitiated).async{[self] in var message: String?; var restoreFailed = false; var cycles: UInt64 = 0; let start = ProcessInfo.processInfo.systemUptime; let needsTiming = !manual && !testOnly; let deadline = needsTiming && limit > 0 ? start + Double(limit) : Double.greatestFiniteMagnitude;func done()->Bool{self.shouldStop() || ProcessInfo.processInfo.systemUptime>=deadline};do{if testOnly{try self.setState(mode:mode,iface:iface,blocked:true,advanced:adv,preset:preset);self.sleepCancelable(750,deadline:deadline);try self.setState(mode:mode,iface:iface,blocked:false,advanced:adv,preset:preset)}else if manual{try self.setState(mode:mode,iface:iface,blocked:true,advanced:adv,preset:preset);while !done(){self.sleepCancelable(700,deadline:deadline);if adv && !done(){try self.setState(mode:mode,iface:iface,blocked:true,advanced:true,preset:preset)}else if mode == .zoomKick && !done(){try self.setState(mode:mode,iface:iface,blocked:true,advanced:false,preset:preset)}}}else if let timing{while !done() && (unlimited || cycles<count){try self.setState(mode:mode,iface:iface,blocked:true,advanced:adv,preset:preset);self.sleepCancelable(timing.duration(blocked:true),deadline:deadline);if done(){break};try self.setState(mode:mode,iface:iface,blocked:false,advanced:adv,preset:preset);cycles+=1;self.sleepCancelable(timing.duration(blocked:false),deadline:deadline)}}}catch{message=error.localizedDescription};do{try self.engine.restore()}catch{restoreFailed=true;message=(message ?? "")+"\nRestoration failed: "+error.localizedDescription};let final=message,failed=restoreFailed,completed=cycles,canceled=self.shouldStop();DispatchQueue.main.async{self.running=false;self.recoveryFailed=failed;self.setRunningUI(false);self.updateModeUI();self.statusLabel.stringValue=failed ? "Restoration failed — quit to retry" : testOnly ? (final != nil ? "Test failed — restored" : canceled ? "Test canceled — restored":"Filter check complete — restored") : "Restored • \(completed) cycles";if let final{self.showError(final)};if self.closing{NSApp.reply(toApplicationShouldTerminate:!failed);self.closing=false}}}
    }
    private func setState(mode:NTMode,iface:String,blocked:Bool,advanced:Bool,preset:AdvancedPreset)throws{if blocked && shouldStop(){return};if advanced{if blocked{let n=try engine.applyAdvanced(interface:iface,preset:preset);guard n>0 else{throw failure("No active matching app connections found. Use Identify traffic and retry while the app is connected.")}}else{try engine.pf.clear()}}else{switch mode{case .fast:try engine.setFast(interface:iface,blocked:blocked);case .adapter:try engine.setAdapter(interface:iface,down:blocked);case .zoomLag,.zoomKick:if blocked{let n=try engine.applyZoomBlock(interface:iface);guard n>0 else{throw failure("No active Zoom connections found.")}}else{try engine.pf.clear()};case .meetLag,.meetHold:try engine.setMeet(interface:iface,blocked:blocked)}};DispatchQueue.main.async{self.statusLabel.stringValue=blocked ? "OFF / blocked":"ON / allowed"}}
    private func sleepCancelable(_ ms:Int,deadline:Double){let end=min(ProcessInfo.processInfo.systemUptime+Double(ms)/1000,deadline);while !shouldStop(){let remaining=end-ProcessInfo.processInfo.systemUptime;if remaining<=0{break};usleep(useconds_t(min(remaining,0.05)*1_000_000))}}
    private func shouldStop()->Bool{lock.lock();defer{lock.unlock()};return stopFlag};private func requestStop(){lock.lock();stopFlag=true;lock.unlock();statusLabel.stringValue="Restoring…"}
    private func setRunningUI(_ on:Bool){for c in [adapterBox,modeBox,behaviorBox,hotKeyBox]{c.isEnabled = !on};for c in [offField,onField,offMax,onMax,countField,limitField]{c.isEnabled = !on};for c in [randomCheck,unlimitedCheck,testButton,refreshButton,advancedCheck,configureButton]{c.isEnabled = !on};stopButton.isEnabled=on;startButton.title=on ? "Restore":"Start"}
    private func showError(_ m:String){let a=NSAlert();a.messageText="ihatemeetings";a.informativeText=m;a.alertStyle = .warning;a.runModal()}
    @objc private func openEditor(){if let e=editor{e.makeKeyAndOrderFront(nil);return};guard !running else{return};let p=NSPanel(contentRect:NSRect(x:0,y:0,width:840,height:480),styleMask:[.titled,.closable,.utilityWindow],backing:.buffered,defer:false);p.title="Advanced packet filters — ihatemeetings 1.5.3";p.center();editor=p;p.delegate=self;let host=p.contentView!
        func add(_ v:NSView,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat=24){v.frame=NSRect(x:x,y:y,width:w,height:h);host.addSubview(v);if let c=v as?NSControl{c.font=NSFont.systemFont(ofSize:12)}}
        func lab(_ s:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat){add(NSTextField(labelWithString:s),x,y,w,18)}
        let pb=NSPopUpButton();pb.addItems(withTitles:(1...5).map{"Preset \($0)"});add(pb,108,432,180);presetBox=pb;pb.target=self;pb.action=#selector(editorPresetChanged);lab("Preset",16,437,84)
        let af=NSTextField();add(af,108,388,584);appField=af;let browse=NSButton(title:"Browse app",target:self,action:#selector(editorBrowse));add(browse,704,388,120);lab("Application",16,393,84)
        let proto=NSPopUpButton();proto.addItems(withTitles:["Any","TCP","UDP"]);add(proto,108,344,140);protoBox=proto;lab("Protocol",16,349,84);let dir=NSPopUpButton();dir.addItems(withTitles:["Both","Outbound","Inbound"]);add(dir,364,344,150);directionBox=dir;lab("Direction",272,349,84);let lp=NSTextField();add(lp,704,344,120);localPortField=lp;lab("Local port",604,349,92)
        let rf=NSTextField();add(rf,144,300,400);remoteField=rf;lab("Remote IP/CIDR",16,305,120);let rp=NSTextField();add(rp,704,300,120);remotePortField=rp;lab("Remote port",596,305,100)
        let identify=NSButton(title:"Identify app traffic",target:self,action:#selector(editorIdentify));add(identify,16,252,184);let use=NSButton(title:"Use selected connection",target:self,action:#selector(editorUseFlow));add(use,212,252,216)
        let flows=NSPopUpButton();add(flows,16,200,808);flowBox=flows;let note=NSTextField(wrappingLabelWithString:"Inspector shows active TCP/UDP connection metadata owned by the selected app. Unconnected UDP sockets do not expose a remote endpoint through lsof.");note.textColor = .secondaryLabelColor;add(note,16,104,808,74)
        let save=NSButton(title:"Save preset",target:self,action:#selector(editorSave));add(save,576,28,116,32);let close=NSButton(title:"Close",target:self,action:#selector(editorClose));add(close,704,28,120,32);loadEditorPreset();window.beginSheet(p,completionHandler:nil)
    }
    private func editorRead()->Bool{guard let af=appField,let proto=protoBox,let dir=directionBox,let lp=localPortField,let rf=remoteField,let rp=remotePortField else{return false};let l=lp.stringValue.isEmpty ? 0:Int(lp.stringValue) ?? -1,r=rp.stringValue.isEmpty ? 0:Int(rp.stringValue) ?? -1;guard (0...65535).contains(l),(0...65535).contains(r) else{showError("Ports must be 1–65535, or blank for any.");return false};guard rf.stringValue.isEmpty || IPNetwork(rf.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)) != nil else{showError("Remote must be a numeric IPv4/IPv6 address or CIDR.");return false};presets[currentPreset]=AdvancedPreset(app:af.stringValue,proto:proto.indexOfSelectedItem,direction:dir.indexOfSelectedItem,localPort:l,remote:rf.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),remotePort:r);return true}
    private func loadEditorPreset(){guard let pb=presetBox,let af=appField,let proto=protoBox,let dir=directionBox,let lp=localPortField,let rf=remoteField,let rp=remotePortField else{return};pb.selectItem(at:currentPreset);let p=presets[currentPreset];af.stringValue=p.app;proto.selectItem(at:p.proto);dir.selectItem(at:p.direction);lp.stringValue=p.localPort == 0 ? "":String(p.localPort);rf.stringValue=p.remote;rp.stringValue=p.remotePort == 0 ? "":String(p.remotePort);flowBox?.removeAllItems();inspected=[]}
    @objc private func editorPresetChanged(){let next=max(0,min(4,presetBox?.indexOfSelectedItem ?? 0));guard editorRead() else{presetBox?.selectItem(at:currentPreset);return};savePreset(currentPreset);currentPreset=next;loadEditorPreset();updateModeUI()}
    @objc private func editorBrowse(){let o=NSOpenPanel();o.canChooseFiles=true;o.canChooseDirectories=true;o.allowsMultipleSelection=false;o.prompt="Choose";if o.runModal() == .OK,let u=o.url{var path=u.standardized.path;if u.pathExtension.lowercased() == "app",let e=Bundle(url:u)?.executableURL{path=e.standardized.path};appField?.stringValue=path}}
    @objc private func editorIdentify(){guard editorRead() else{return};let p=presets[currentPreset];guard !p.app.isEmpty else{showError("Choose an application first.");return};let pids=engine.pids(forExecutable:p.app);inspectedApp=p.app;inspected=connections(for:pids);flowBox?.removeAllItems();flowBox?.addItems(withTitles:inspected.map(\.label));if inspected.isEmpty{showError("No active TCP connections or UDP sockets were found for that application.")}}
    @objc private func editorUseFlow(){guard let i=flowBox?.indexOfSelectedItem,inspected.indices.contains(i) else{return};guard appField?.stringValue==inspectedApp else{showError("Identify traffic again after changing the application.");return};let c=inspected[i];protoBox?.selectItem(at:c.proto == "tcp" ? 1:2);localPortField?.stringValue=String(c.localPort);remoteField?.stringValue=c.remoteHost;remotePortField?.stringValue=c.remotePort>0 ? String(c.remotePort):""}
    @objc private func editorSave(){if editorRead(){savePreset(currentPreset);updateModeUI();let a=NSAlert();a.messageText="Preset saved";a.runModal()}}
    @objc private func editorClose(){guard editorRead() else{return};savePreset(currentPreset);updateModeUI();if let panel=editor{window.endSheet(panel);panel.orderOut(nil)};editor=nil}
#if UI_TEST
    func verifyNativeUI() -> Int32 {
        buildUI()
        adapterBox.addItem(withTitle: "Wi-Fi (en0)")
        var failures = 0
        func verify(_ target: NSWindow, _ file: String) {
            let host = target.contentView!
            let views = host.subviews.filter { !$0.isHidden }
            for (i,v) in views.enumerated() {
                if !host.bounds.contains(v.frame) { print("FAIL outside client: \(v)"); failures += 1 }
                for other in views.prefix(i) where v.frame.intersects(other.frame) {
                    print("FAIL overlapping controls: \(v) and \(other)"); failures += 1
                }
                if let label = v as? NSTextField, !label.isEditable, label != detailLabel {
                    let text = label.stringValue as NSString
                    let rect = text.boundingRect(with: NSSize(width: label.bounds.width,height: 1000),options: [.usesLineFragmentOrigin],attributes: [.font:label.font!])
                    if ceil(rect.height) > label.bounds.height { print("FAIL clipped label: \(text)"); failures += 1 }
                }
                if let button = v as? NSButton, !(button is NSPopUpButton), button.intrinsicContentSize.width > button.frame.width {
                    print("FAIL clipped button: \(button.title), needs \(button.intrinsicContentSize.width), has \(button.frame.width)"); failures += 1
                }
            }
            host.displayIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png,properties: [:]) { try? data.write(to: URL(fileURLWithPath: file)) }
            }
        }
        window.makeKeyAndOrderFront(nil)
        for mode in 0..<6 {
            modeBox.selectItem(at: mode)
            for behavior in 0..<2 { behaviorBox.selectItem(at:behavior);updateModeUI();verify(window,"mac-main.png") }
        }
        advancedCheck.state = .on; updateModeUI();verify(window,"mac-advanced.png")
        openEditor()
        if let panel = editor { verify(panel,"mac-config.png");editorClose() } else { failures += 1 }
        print("Native AppKit geometry and text checks: \(failures) failures")
        return failures == 0 ? 0 : 1
    }
#endif

}

@main
struct IHateMeetingsMain {
    static func main() {
#if UI_TEST
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        exit(delegate.verifyNativeUI())
#else
        ensureElevated()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
#endif
    }
}
