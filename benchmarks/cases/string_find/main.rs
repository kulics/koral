fn main() {
    let start = std::time::Instant::now();
    let mut s = String::with_capacity(8_000_000);
    for _ in 0..1_000_000 {
        s.push_str("abcdefgh");
    }
    let mut hits = 0usize;
    let mut off = 0usize;
    while let Some(idx) = s[off..].find("abc") {
        hits += 1;
        off += idx + 1;
    }
    println!("RESULT {} {}", hits, start.elapsed().as_nanos());
}
