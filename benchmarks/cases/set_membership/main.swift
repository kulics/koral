import Foundation

let n = 500_000
let start = DispatchTime.now()
var s = Set<Int>()
s.reserveCapacity(n)
for i in 0..<n {
    s.insert(i)
}
var hits = 0
for i in 0..<(2*n) {
    if s.contains(i % n) {
        hits += 1
    }
}
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(hits) \(ns)")
