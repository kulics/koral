package main

import (
	"fmt"
	"time"
)

type pair struct {
	a int64
	b int64
}

func main() {
	n := 5_000_000
	start := time.Now()
	xs := make([]pair, 0, n)
	for i := 0; i < n; i++ {
		xs = append(xs, pair{int64(i), int64(i % 7)})
	}
	var sum int64
	for _, p := range xs {
		sum += p.a * p.b
	}
	fmt.Printf("RESULT %d %d\n", sum, time.Since(start).Nanoseconds())
}
