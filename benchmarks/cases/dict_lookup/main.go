package main

import (
	"fmt"
	"strconv"
	"time"
)

func main() {
	n := 500_000
	start := time.Now()
	d := make(map[string]int, n)
	for i := 0; i < n; i++ {
		d["k"+strconv.Itoa(i)] = i
	}
	sum := 0
	for i := 0; i < n; i++ {
		if v, ok := d["k"+strconv.Itoa(i)]; ok {
			sum += v
		}
	}
	fmt.Printf("RESULT %d %d\n", sum, time.Since(start).Nanoseconds())
}
