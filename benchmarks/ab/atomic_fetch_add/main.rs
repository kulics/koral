use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Instant;

fn main() {
    let threads: u64 = 8;
    let per_thread: u64 = 1_000_000;
    let counter = Arc::new(AtomicI64::new(0));
    let start = Instant::now();
    let handles: Vec<_> = (0..threads)
        .map(|_| {
            let c = Arc::clone(&counter);
            thread::spawn(move || {
                for _ in 0..per_thread {
                    c.fetch_add(1, Ordering::SeqCst);
                }
            })
        })
        .collect();
    for h in handles {
        h.join().unwrap();
    }
    println!(
        "RESULT {} {}",
        counter.load(Ordering::SeqCst),
        start.elapsed().as_nanos()
    );
}
