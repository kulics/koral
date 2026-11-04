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
	fmt.Printf("RESULT %d %d\n", len(xs), time.Since(start).Nanoseconds())
}
