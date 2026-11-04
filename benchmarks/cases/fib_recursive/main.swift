import Foundation

func fib(_ n: Int) -> Int {
    if n < 2 { return n }
    return fib(n - 1) + fib(n - 2)
}

let start = DispatchTime.now()
let v = fib(27)
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(v) \(ns)")
