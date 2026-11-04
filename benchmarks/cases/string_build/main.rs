fn main() {
    let n: usize = 300_000;
    let start = std::time::Instant::now();
    let mut s = String::with_capacity(16);
    for i in 0..n {
        s.push_str("abc");
        s.push_str(&i.to_string());
    }
    println!("RESULT {} {}", s.len(), start.elapsed().as_nanos());
}
