import Foundation

let n: Int64 = 3_500_000
let start = DispatchTime.now()
var sum: Int64 = 0
var i: Int64 = 0
while i < n {
    if i % 3 == 0 {
        sum += i * i
    }
    i += 1
}
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(sum) \(ns)")
