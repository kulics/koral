package main

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

// Capturing regex scan throughput: compile once, then walk every match of a
// 5-group pattern over a ~5 MB deterministic text and checksum the spans.
func main() {
	var b strings.Builder
	b.Grow(6_000_000)
	for i := 0; i < 250_000; i++ {
		fmt.Fprintf(&b, "user%d@host%d.org ", i%1000, i%97)
	}
	text := b.String()

	re := regexp.MustCompile(`([a-z]+)([0-9]+)@([a-z]+)([0-9]+)\.([a-z]+)`)

	start := time.Now()
	var sum, count uint64
	for _, m := range re.FindAllStringSubmatchIndex(text, -1) {
		count++
		for _, v := range m {
			if v >= 0 {
				sum += uint64(v)
			}
		}
	}
	elapsed := time.Since(start).Nanoseconds()
	fmt.Printf("RESULT %d %d\n", sum+count, elapsed)
}
