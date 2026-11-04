import Foundation

let n = 500_000
let start = DispatchTime.now()
var d = [String: Int]()
d.reserveCapacity(n)
for i in 0..<n {
    d["k\(i)"] = i
}
var sum = 0
for i in 0..<n {
    if let v = d["k\(i)"] {
        sum += v
    }
}
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(sum) \(ns)")
