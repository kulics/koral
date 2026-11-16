package main

import (
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

func main() {
	const threads = 8
	const perThread = 1_000_000
	var counter int64
	start := time.Now()
	var wg sync.WaitGroup
	for t := 0; t < threads; t++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < perThread; i++ {
				atomic.AddInt64(&counter, 1)
			}
		}()
	}
	wg.Wait()
	fmt.Printf("RESULT %d %d\n", counter, time.Since(start).Nanoseconds())
}
