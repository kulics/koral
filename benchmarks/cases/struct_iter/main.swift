import Foundation

struct Pair {
    var a: Int64
    var b: Int64
}

let n = 5_000_000
let start = DispatchTime.now()
var xs = [Pair]()
xs.reserveCapacity(n)
for i in 0..<n {
    xs.append(Pair(a: Int64(i), b: Int64(i % 7)))
}
var sum: Int64 = 0
for p in xs {
    sum += p.a * p.b
}
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(sum) \(ns)")
