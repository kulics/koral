package main

import (
	"fmt"
	"time"
)

func main() {
	n := 5_000_000
	start := time.Now()
	xs := make([]int, 0, n)
	for i := 0; i < n; i++ {
		xs = append(xs, i)
	}
	sum := 0
	for j := 0; j < len(xs); j++ {
		sum += xs[j]
	}
	fmt.Printf("RESULT %d %d\n", sum, time.Since(start).Nanoseconds())
}
