import Foundation

let n = 5_000_000
let start = DispatchTime.now()
var xs = [Int]()
xs.reserveCapacity(n)
for i in 0..<n {
    xs.append(i)
}
var sum = 0
for v in xs {
    sum += v
}
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(sum) \(ns)")
