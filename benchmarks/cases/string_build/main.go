package main

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

func main() {
	n := 300_000
	start := time.Now()
	var b strings.Builder
	b.Grow(16)
	for i := 0; i < n; i++ {
		b.WriteString("abc")
		b.WriteString(strconv.Itoa(i))
	}
	s := b.String()
	fmt.Printf("RESULT %d %d\n", len(s), time.Since(start).Nanoseconds())
}
