use std::collections::HashSet;

fn main() {
    let n: i64 = 500_000;
    let start = std::time::Instant::now();
    let mut s = HashSet::with_capacity(n as usize);
    for i in 0..n {
        s.insert(i);
    }
    let mut hits = 0i64;
    for i in 0..(2 * n) {
        if s.contains(&(i % n)) {
            hits += 1;
        }
    }
    println!("RESULT {} {}", hits, start.elapsed().as_nanos());
}
