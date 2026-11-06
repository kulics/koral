import Foundation

// Capturing regex scan throughput: compile once, then walk every match of a
// 5-group pattern over a ~5 MB deterministic text and checksum the spans.
// NSRegularExpression is ICU -- the C-library bar for this comparison. The
// text is pure ASCII, so UTF-16 offsets equal byte offsets.
func main() {
    var b = ""
    b.reserveCapacity(6_000_000)
    var i = 0
    while i < 250_000 {
        b += "user\(i % 1000)@host\(i % 97).org "
        i += 1
    }
    let text = b

    let re: NSRegularExpression
    do {
        re = try NSRegularExpression(pattern: "([a-z]+)([0-9]+)@([a-z]+)([0-9]+)\\.([a-z]+)")
    } catch {
        print("compile failed")
        exit(1)
    }

    let start = DispatchTime.now().uptimeNanoseconds
    var sum: UInt64 = 0
    var count: UInt64 = 0
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    re.enumerateMatches(in: text, range: range) { m, _, _ in
        guard let m = m else { return }
        count += 1
        for g in 0..<m.numberOfRanges {
            let r = m.range(at: g)
            if r.location != NSNotFound {
                sum += UInt64(r.location) + UInt64(r.location + r.length)
            }
        }
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    print("RESULT \(sum + count) \(elapsed)")
}

main()
