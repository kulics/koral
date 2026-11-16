use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Instant;

fn main() {
    let threads: u64 = 8;
    let per_thread: u64 = 1_000_000;
    let counter = Arc::new(Mutex::new(0i64));
    let start = Instant::now();
    let handles: Vec<_> = (0..threads)
        .map(|_| {
            let c = Arc::clone(&counter);
            thread::spawn(move || {
                for _ in 0..per_thread {
                    let mut v = c.lock().unwrap();
                    *v += 1;
                }
            })
        })
        .collect();
    for h in handles {
        h.join().unwrap();
    }
    println!(
        "RESULT {} {}",
        *counter.lock().unwrap(),
        start.elapsed().as_nanos()
    );
}
