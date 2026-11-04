fn main() {
    let n: i64 = 3_500_000;
    let start = std::time::Instant::now();
    let mut sum: i64 = 0;
    for i in 0..n {
        if i % 3 == 0 {
            sum += i * i;
        }
    }
    println!("RESULT {} {}", sum, start.elapsed().as_nanos());
}
