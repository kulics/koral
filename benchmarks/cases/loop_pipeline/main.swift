import Foundation

let n: Int64 = 3_500_000
let start = DispatchTime.now()
var sum: Int64 = 0
for i in 0..<n {
    if i % 3 == 0 {
        sum += i * i
    }
}
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(sum) \(ns)")
