import Foundation

let n = 300_000
let start = DispatchTime.now()
var s = ""
s.reserveCapacity(16)
for i in 0..<n {
    s += "abc"
    s += String(i)
}
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(s.count) \(ns)")
