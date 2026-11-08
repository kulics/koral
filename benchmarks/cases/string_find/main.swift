import Foundation

let start = DispatchTime.now()
var s = ""
s.reserveCapacity(8_000_000)
for _ in 0..<1_000_000 {
    s += "abcdefgh"
}
var hits = 0
var search = s.startIndex..<s.endIndex
while let r = s.range(of: "abc", options: .literal, range: search) {
    hits += 1
    search = s.index(after: r.lowerBound)..<s.endIndex
}
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(hits) \(ns)")
