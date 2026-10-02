import Foundation
import Darwin

struct IPNetwork {
    let family: Int32
    let bytes: [UInt8]
    let bits: Int
    init?(_ value: String) {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2, let host = parts.first, !host.isEmpty else { return nil }
        let family = host.contains(":") ? AF_INET6 : AF_INET
        var bytes = [UInt8](repeating: 0, count: family == AF_INET6 ? 16 : 4)
        guard String(host).withCString({ inet_pton(family, $0, &bytes) }) == 1 else { return nil }
        let width = bytes.count * 8
        let bits = parts.count == 2 ? Int(parts[1]) : width
        guard let bits = bits, bits >= 0, bits <= width else { return nil }
        self.family = family; self.bytes = bytes; self.bits = bits
    }
    func contains(_ host: String) -> Bool {
        guard let ip = IPNetwork(host), ip.family == family else { return false }
        for i in 0..<bytes.count {
            let count = max(0, min(8, bits-i*8))
            let mask: UInt8 = count == 0 ? 0 : UInt8(255 << (8-count) & 255)
            if bytes[i] & mask != ip.bytes[i] & mask { return false }
        }
        return true
    }
}
struct Connection: Hashable {
    let pid: Int
    let process: String
    let proto: String
    let localHost: String
    let localPort: Int
    let remoteHost: String
    let remotePort: Int
    var label: String { "\(process) [\(pid)]  \(proto.uppercased())  \(localHost):\(localPort) → " + (remoteHost.isEmpty ? "remote not exposed" : "\(remoteHost):\(remotePort)") }
    var key: String { "\(proto)|\(localHost)|\(localPort)|\(remoteHost)|\(remotePort)" }
}
func endpoint(_ input: String) -> (String,Int)? {
    // PF can print IPv6 as address[port]; lsof prints [address]:port.
    var value = input
    if !value.hasPrefix("["), value.hasSuffix("]"), let bracket = value.lastIndex(of: "[") {
        value = String(value[..<bracket]) + ":" + String(value[value.index(after: bracket)..<value.index(before: value.endIndex)])
    }
    guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]), (1...65535).contains(port) else { return nil }
    let host = String(value[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    guard IPNetwork(host) != nil else { return nil }
    return (host,port)
}
// Parse all owners first, then exclude ambiguous/shared bindings instead of guessing.
func parseOwnedConnections(_ output: String, selected: Set<Int>) -> [Connection] {
    var pid = 0, proto = "", process = "", rows: [Connection] = []
    var bindingOwners: [String:Set<Int>] = [:]
    for raw in output.split(separator: "\n") {
        guard let tag = raw.first else { continue }; let value = String(raw.dropFirst())
        if tag == "p" { pid = Int(value) ?? 0; proto = "" }
        if tag == "c" { process = value }
        if tag == "f" { proto = "" }
        if tag == "P" { proto = value.lowercased() }
        if tag != "n" || !["tcp","udp"].contains(proto) || pid <= 0 { continue }
        let parts = value.components(separatedBy: "->")
        // Wildcard/unconnected UDP sockets count as possible competing owners too.
        if let port = parts[0].split(separator: ":").last.flatMap({ Int($0) }), proto == "udp" {
            bindingOwners["udp|\(port)", default: []].insert(pid)
        }
        guard let local = endpoint(parts[0]) else { continue }
        if parts.count == 1 {
            let c = Connection(pid: pid, process: process, proto: proto, localHost: local.0, localPort: local.1, remoteHost: "", remotePort: 0)
            rows.append(c); bindingOwners[c.key, default: []].insert(pid)
            continue
        }
        guard parts.count == 2, let remote = endpoint(parts[1]) else { continue }
        let c = Connection(pid: pid, process: process, proto: proto, localHost: local.0, localPort: local.1, remoteHost: remote.0, remotePort: remote.1)
        rows.append(c); bindingOwners[c.key, default: []].insert(pid)
    }
    return Array(Set(rows.filter { c in
        selected.contains(c.pid) && bindingOwners[c.key]?.count == 1 && (c.proto != "udp" || bindingOwners["udp|\(c.localPort)"]?.count == 1)
    })).sorted { $0.label < $1.label }
}

// Match complete, non-NAT endpoint pairs before selecting a PF state ID.
func matchingStateIDs(_ output: String, connections: [Connection]) -> [String] {
    var match = false, ids: [String] = []
    for raw in output.split(separator:"\n") {
        let line = String(raw), words = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if let first=raw.first, !first.isWhitespace {match=false}
        if words.contains("tcp") || words.contains("udp") {
            match = false
            guard !line.contains("("), let pi = words.firstIndex(where: { $0 == "tcp" || $0 == "udp" }), words.count > pi+3,
                  let a = endpoint(words[pi+1]), let b = endpoint(words[pi+3]), ["->","<-"].contains(words[pi+2]) else { continue }
            match = connections.contains { c in
                func eq(_ x:(String,Int),_ host:String,_ port:Int)->Bool { x.1 == port && IPNetwork(host)?.contains(x.0) == true }
                return c.proto == words[pi] && ((eq(a,c.localHost,c.localPort) && eq(b,c.remoteHost,c.remotePort)) || (eq(b,c.localHost,c.localPort) && eq(a,c.remoteHost,c.remotePort)))
            }
        }
        if match, let index = words.firstIndex(of:"id:"), words.count > index+1 {
            let id = words[index+1];guard id.count <= 16, UInt64(id,radix:16) != nil else {continue}
            guard UInt64(id, radix: 16) != 0,
                  let ci = words.firstIndex(of: "creatorid:"), words.count > ci+1,
                  let creator = UInt32(words[ci+1], radix: 16), creator != 0 else { continue }
            let target = id + "/" + words[ci+1]
            ids.append(target);match=false
        }
    }
    return ids
}
