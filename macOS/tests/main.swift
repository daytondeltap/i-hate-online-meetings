import Foundation
func check(_ b: @autoclosure () -> Bool) { precondition(b()) }
check(Timing(off: 0, offMax: 500, on: 100, onMax: 200, random: true) == nil)
check(Timing(off: 500, offMax: 499, on: 100, onMax: 200, random: true) == nil)
check(Timing(off: 10, offMax: 20, on: 200, onMax: 199, random: true) == nil)
check(Timing(off: 10, offMax: 86_400_001, on: 10, onMax: 10, random: true) == nil)
let fixed = Timing(off: 100, offMax: 0, on: 200, onMax: 0, random: false)!
check(fixed.duration(blocked: true) == 100); check(fixed.duration(blocked: false) == 200)
let equal = Timing(off: 100, offMax: 100, on: 200, onMax: 200, random: true)!
check(equal.duration(blocked: true) == 100); check(equal.duration(blocked: false) == 200)
let random = Timing(off: 10, offMax: 20, on: 200, onMax: 400, random: true)!
for _ in 0..<1000 {
 check((10...20).contains(random.duration(blocked: true)))
 check((200...400).contains(random.duration(blocked: false)))
}
let rules = meetRules(interface: "en0")
check(rules.split(separator: "\n").count == 12)
check(!rules.contains("from any to any"))
for range in meetRanges { check(rules.contains("to " + range)); check(rules.contains("from " + range)) }
if CommandLine.arguments.contains("--rules") { print(rules, terminator: "") }
else { print("PASS: timing bounds, random phases and twelve scoped Meet rules") }

// App isolation: same server and protocol must not select a different local port.
let sockets = "p42\ncAppA\nf1\nPTCP\nn10.0.0.2:50001->192.0.2.7:443\np43\ncAppB\nf2\nPTCP\nn10.0.0.2:50002->192.0.2.7:443\n"
let owned = parseOwnedConnections(sockets, selected: [42])
check(owned.count == 1 && owned[0].localPort == 50001 && owned[0].pid == 42)
let ambiguous = "p42\nf1\nPUDP\nn10.0.0.2:51000->192.0.2.7:443\np43\nf2\nPUDP\nn*:51000\n"
check(parseOwnedConnections(ambiguous, selected: [42]).isEmpty)
let states = "all tcp 10.0.0.2:50001 -> 192.0.2.7:443 ESTABLISHED:ESTABLISHED\n   id: 0123456789abcdef creatorid: 00000001\nall tcp 10.0.0.2:50002 -> 192.0.2.7:443 ESTABLISHED:ESTABLISHED\n   id: 0123456789abcdee creatorid: 00000001\n"
check(matchingStateIDs(states, connections: owned) == ["0123456789abcdef/00000001"])
check(matchingStateIDs(states.replacingOccurrences(of: "creatorid: 00000001", with: "creatorid: 00000000"), connections: owned).isEmpty)
check(matchingStateIDs("all tcp 10.0.0.2:50001 (10.1.1.1:1) -> 192.0.2.7:443\n   id: 0123456789abcdef creatorid: 00000001", connections: owned).isEmpty)
check(matchingStateIDs(states.replacingOccurrences(of: "tcp", with: "udp"), connections: owned).isEmpty)
check(IPNetwork("192.0.2.0/-1") == nil)
check(IPNetwork("192.0.2.0/24/7") == nil)
check(IPNetwork("192.0.2.0/24")!.contains("192.0.2.255"))
check(!IPNetwork("192.0.2.0/24")!.contains("192.0.3.0"))
check(IPNetwork("2001:db8::/33")!.contains("2001:db8:7fff::1"))
check(!IPNetwork("2001:db8::/33")!.contains("2001:db8:8000::1"))
check(endpoint("2001:db8::1[443]")?.1 == 443)
check(endpoint("[2001:db8::1]:443")?.0 == "2001:db8::1")
let ipv6 = Connection(pid: 42, process: "AppA", proto: "tcp", localHost: "2001:db8::1", localPort: 50001, remoteHost: "2001:db8::2", remotePort: 443)
check(matchingStateIDs("all tcp 2001:db8::1[50001] -> 2001:db8::2[443] ESTABLISHED:ESTABLISHED\n   id: 123456789abcdef0 creatorid: 00000001", connections: [ipv6]) == ["123456789abcdef0/00000001"])
if !CommandLine.arguments.contains("--rules") { print("PASS: app ownership, shared UDP exclusion, exact PF state selection, IPv4/IPv6 and CIDR validation") }
