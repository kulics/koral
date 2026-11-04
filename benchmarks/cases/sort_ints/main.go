package main

import (
	"fmt"
	"sort"
	"time"
)

func main() {
	n := 1_000_000
	start := time.Now()
	xs := make([]int, 0, n)
	var state int64 = 42
	for i := 0; i < n; i++ {
		state = (state*1103515245 + 12345) % 2147483648
		xs = append(xs, int(state%2147483647))
	}
	sort.Ints(xs)
	fmt.Printf("RESULT %d %d\n", len(xs), time.Since(start).Nanoseconds())
}
