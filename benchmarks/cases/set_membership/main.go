package main

import (
	"fmt"
	"time"
)

func main() {
	n := 500_000
	start := time.Now()
	s := make(map[int]struct{}, n)
	for i := 0; i < n; i++ {
		s[i] = struct{}{}
	}
	hits := 0
	for i := 0; i < 2*n; i++ {
		if _, ok := s[i%n]; ok {
			hits++
		}
	}
	fmt.Printf("RESULT %d %d\n", hits, time.Since(start).Nanoseconds())
}
