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
