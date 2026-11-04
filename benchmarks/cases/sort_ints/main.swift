import Foundation

let n = 1_000_000
let start = DispatchTime.now()
var xs = [Int]()
xs.reserveCapacity(n)
var state: Int64 = 42
for _ in 0..<n {
    state = (state * 1103515245 + 12345) % 2147483648
    xs.append(Int(state % 2147483647))
}
xs.sort()
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds

// Verify the result really is sorted, then checksum it in order
// (precondition, not assert: assert is compiled out under -O).
var checksum = 0
var prev = 0
for v in xs {
    precondition(v >= prev, "sort_ints: output must be sorted")
    checksum = (checksum * 131 + v) % 2147483648
    prev = v
}
print("RESULT \(checksum) \(ns)")
