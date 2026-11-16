package main

import (
	"fmt"
	"sync"
	"time"
)

func main() {
	const threads = 8
	const perThread = 1_000_000
	var mu sync.Mutex
	var counter int64
	start := time.Now()
	var wg sync.WaitGroup
	for t := 0; t < threads; t++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < perThread; i++ {
				mu.Lock()
				counter++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	fmt.Printf("RESULT %d %d\n", counter, time.Since(start).Nanoseconds())
}
