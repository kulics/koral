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

// Verify the result really is sorted, then checksum the strings' bytes in order
// (precondition, not assert: assert is compiled out under -O).
var checksum = 0
var prev = ""
for v in xs {
    precondition(v >= prev, "sort_strings: output must be sorted")
    var g = 0
    for b in v.utf8 {
        g = (g * 131 + Int(b)) % 2147483648
    }
    checksum = (checksum * 131 + g) % 2147483648
    prev = v
}
print("RESULT \(checksum) \(ns)")
