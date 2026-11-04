package main

import (
	"fmt"
	"time"
)

func main() {
	var n int64 = 3_500_000
	start := time.Now()
	var sum int64
	for i := int64(0); i < n; i++ {
		if i%3 == 0 {
			sum += i * i
		}
	}
	fmt.Printf("RESULT %d %d\n", sum, time.Since(start).Nanoseconds())
}
