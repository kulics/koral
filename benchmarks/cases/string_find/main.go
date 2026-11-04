package main

import (
	"fmt"
	"strings"
	"time"
)

func main() {
	start := time.Now()
	var b strings.Builder
	b.Grow(8_000_000)
	for i := 0; i < 1_000_000; i++ {
		b.WriteString("abcdefgh")
	}
	s := b.String()
	hits := 0
	off := 0
	for {
		idx := strings.Index(s[off:], "abc")
		if idx < 0 {
			break
		}
		hits++
		off += idx + 1
	}
	fmt.Printf("RESULT %d %d\n", hits, time.Since(start).Nanoseconds())
}
