struct Pair {
    a: i64,
    b: i64,
}

fn main() {
    let n: usize = 5_000_000;
    let start = std::time::Instant::now();
    let mut xs: Vec<Pair> = Vec::with_capacity(n);
    for i in 0..n as i64 {
        xs.push(Pair { a: i, b: i % 7 });
    }
    let mut sum: i64 = 0;
    for p in &xs {
        sum += p.a * p.b;
    }
    println!("RESULT {} {}", sum, start.elapsed().as_nanos());
}
