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
	elapsed := time.Since(start).Nanoseconds()

	// Verify the result really is sorted, then checksum it in order.
	checksum := 0
	prev := 0
	for _, v := range xs {
		if v < prev {
			panic("sort_ints: output must be sorted")
		}
		checksum = (checksum*131 + v) % 2147483648
		prev = v
	}
	fmt.Printf("RESULT %d %d\n", checksum, elapsed)
}
