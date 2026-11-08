fn main() {
    let n: usize = 5_000_000;
    let start = std::time::Instant::now();
    let mut xs: Vec<i64> = Vec::with_capacity(n);
    for i in 0..n as i64 {
        xs.push(i);
    }
    let mut sum: i64 = 0;
    for &v in &xs {
        sum += v;
    }
    println!("RESULT {} {}", sum, start.elapsed().as_nanos());
}
