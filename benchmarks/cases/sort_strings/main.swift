import Foundation

let n = 200_000
let start = DispatchTime.now()
var xs = [String]()
xs.reserveCapacity(n)
var state: Int64 = 7
for _ in 0..<n {
    state = (state * 1103515245 + 12345) % 2147483648
    xs.append("s\(String(state % 2147483647))")
}
xs.sort()
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(xs.count) \(ns)")
