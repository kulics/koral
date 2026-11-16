import Foundation
import Synchronization

let threads = 8
let perThread = 1_000_000
let counter = Atomic<Int64>(0)
let start = DispatchTime.now()
let group = DispatchGroup()
for _ in 0..<threads {
    group.enter()
    let t = Thread {
        for _ in 0..<perThread {
            counter.wrappingAdd(1, ordering: .sequentiallyConsistent)
        }
        group.leave()
    }
    t.start()
}
group.wait()
let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
print("RESULT \(counter.load(ordering: .sequentiallyConsistent)) \(ns)")
