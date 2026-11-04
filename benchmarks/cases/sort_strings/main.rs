fn main() {
    let n: usize = 200_000;
    let start = std::time::Instant::now();
    let mut xs: Vec<String> = Vec::with_capacity(n);
    let mut state: i64 = 7;
    for _ in 0..n {
        state = (state * 1103515245 + 12345) % 2147483648;
        xs.push(format!("s{}", state % 2147483647));
    }
    xs.sort();
    println!("RESULT {} {}", xs.len(), start.elapsed().as_nanos());
}
