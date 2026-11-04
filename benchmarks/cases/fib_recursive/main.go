package main

import (
	"fmt"
	"time"
)

func fib(n int) int {
	if n < 2 {
		return n
	}
	return fib(n-1) + fib(n-2)
}

func main() {
	start := time.Now()
	v := fib(27)
	fmt.Printf("RESULT %d %d\n", v, time.Since(start).Nanoseconds())
}
