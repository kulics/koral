fn main() {
    let n: usize = 1_000_000;
    let start = std::time::Instant::now();
    let mut xs: Vec<i64> = Vec::with_capacity(n);
    let mut state: i64 = 42;
    for _ in 0..n {
        state = (state * 1103515245 + 12345) % 2147483648;
        xs.push(state % 2147483647);
    }
    xs.sort();
    let ns = start.elapsed().as_nanos();

    // Verify the result really is sorted, then checksum it in order.
    let mut checksum: i64 = 0;
    let mut prev: i64 = 0;
    for &v in &xs {
        assert!(v >= prev, "sort_ints: output must be sorted");
        checksum = (checksum * 131 + v) % 2147483648;
        prev = v;
    }
    println!("RESULT {} {}", checksum, ns);
}
