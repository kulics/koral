fn fib(n: i64) -> i64 {
    if n < 2 {
        n
    } else {
        fib(n - 1) + fib(n - 2)
    }
}

fn main() {
    let start = std::time::Instant::now();
    let v = fib(27);
    println!("RESULT {} {}", v, start.elapsed().as_nanos());
}
