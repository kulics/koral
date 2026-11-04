package main

import (
	"fmt"
	"sort"
	"strconv"
	"time"
)

func main() {
	n := 200_000
	start := time.Now()
	xs := make([]string, 0, n)
	var state int64 = 7
	for i := 0; i < n; i++ {
		state = (state*1103515245 + 12345) % 2147483648
		xs = append(xs, "s"+strconv.FormatInt(state%2147483647, 10))
	}
	sort.Strings(xs)
	elapsed := time.Since(start).Nanoseconds()

	// Verify the result really is sorted, then checksum the strings' bytes in order.
	checksum := 0
	prev := ""
	for _, v := range xs {
		if v < prev {
			panic("sort_strings: output must be sorted")
		}
		g := 0
		for i := 0; i < len(v); i++ {
			g = (g*131+int(v[i])) % 2147483648
		}
		checksum = (checksum*131 + g) % 2147483648
		prev = v
	}
	fmt.Printf("RESULT %d %d\n", checksum, elapsed)
}
