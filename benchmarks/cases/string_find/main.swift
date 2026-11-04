import Foundation

let start = DispatchTime.now()
var s = ""
s.reserveCapacity(8_000_000)
for _ in 0..<1_000_000 {
    s += "abcdefgh"
}
var hits = 0
var off = s.startIndex
while let r = s.range(of: "abc", range: off..<s.endIndex) {
    hits += 1
    off = s.index(after: r.lowerBound)
}
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(hits) \(ns)")
