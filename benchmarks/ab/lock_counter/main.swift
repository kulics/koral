import Foundation

final class Counter: @unchecked Sendable {
    let lock = NSLock()
    var value: Int64 = 0
}

let threads = 8
let perThread = 1_000_000
let counter = Counter()
let start = DispatchTime.now()
let group = DispatchGroup()
for _ in 0..<threads {
    group.enter()
    let t = Thread {
        for _ in 0..<perThread {
            counter.lock.lock()
            counter.value += 1
            counter.lock.unlock()
        }
        group.leave()
    }
    t.start()
}
group.wait()
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(counter.value) \(ns)")
