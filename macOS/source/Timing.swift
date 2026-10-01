import Foundation

let meetRanges = ["74.125.250.0/24", "74.125.247.128/32", "142.250.82.0/24", "2001:4860:4864:5::/64", "2001:4860:4864:4:8000::/128", "2001:4860:4864:6::/64"]
func meetRules(interface: String) -> String {
    meetRanges.map { range in
        let family = range.contains(":") ? "inet6" : "inet"
        return "block drop quick on \(interface) \(family) from any to \(range)\nblock drop quick on \(interface) \(family) from \(range) to any\n"
    }.joined()
}
struct Timing {
    let off: ClosedRange<Int>
    let on: ClosedRange<Int>
    init?(off: Int, offMax: Int, on: Int, onMax: Int, random: Bool) {
        let hiOff = random ? offMax : off, hiOn = random ? onMax : on
        guard off >= 10, on >= 10, hiOff >= off, hiOn >= on, hiOff <= 86_400_000, hiOn <= 86_400_000 else { return nil }
        self.off = off...hiOff; self.on = on...hiOn
    }
    func duration(blocked: Bool) -> Int { Int.random(in: blocked ? off : on) }
}
