use std::collections::HashMap;

fn main() {
    let n: i64 = 500_000;
    let start = std::time::Instant::now();
    let mut d = HashMap::with_capacity(n as usize);
    for i in 0..n {
        d.insert(format!("k{}", i), i);
    }
    let mut sum = 0i64;
    for i in 0..n {
        if let Some(v) = d.get(&format!("k{}", i)) {
            sum += v;
        }
    }
    println!("RESULT {} {}", sum, start.elapsed().as_nanos());
}
