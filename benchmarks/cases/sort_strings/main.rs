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
    let ns = start.elapsed().as_nanos();

    // Verify the result really is sorted, then checksum the strings' bytes in order.
    let mut checksum: i64 = 0;
    let mut prev = String::new();
    for v in &xs {
        assert!(*v >= prev, "sort_strings: output must be sorted");
        let mut g: i64 = 0;
        for &b in v.as_bytes() {
            g = (g * 131 + b as i64) % 2147483648;
        }
        checksum = (checksum * 131 + g) % 2147483648;
        prev = v.clone();
    }
    println!("RESULT {} {}", checksum, ns);
}
