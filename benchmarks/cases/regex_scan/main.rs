// Capturing regex scan throughput: compile once, then walk every match of a
// 5-group pattern over a ~5 MB deterministic text and checksum the spans.
fn main() {
    let mut b = String::with_capacity(6_000_000);
    for i in 0..250_000u64 {
        b.push_str(&format!("user{}@host{}.org ", i % 1000, i % 97));
    }
    let text = b;

    let re = regex::Regex::new(r"([a-z]+)([0-9]+)@([a-z]+)([0-9]+)\.([a-z]+)").unwrap();

    let start = std::time::Instant::now();
    let mut sum: u64 = 0;
    let mut count: u64 = 0;
    for caps in re.captures_iter(&text) {
        count += 1;
        for i in 0..caps.len() {
            if let Some(m) = caps.get(i) {
                sum += m.start() as u64 + m.end() as u64;
            }
        }
    }
    let elapsed = start.elapsed().as_nanos();
    println!("RESULT {} {}", sum + count, elapsed);
}
