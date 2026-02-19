package main

import (
	"bytes"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func main() {
	force := flag.Bool("force", false, "rebuild koralfmt even if binary already exists")
	flag.Parse()

	root, err := findRepoRoot()
	if err != nil {
		fatal(err)
	}

	fmtExe := filepath.Join(root, "bin", exeName("koralfmt"))
	if !*force {
		if _, err := os.Stat(fmtExe); err == nil {
			fmt.Printf("koralfmt already prepared: %s\n", fmtExe)
			return
		}
	}

	koralc := filepath.Join(root, "bin", exeName("koralc"))
	if _, err := os.Stat(koralc); err != nil {
		fatal(fmt.Errorf("koralc binary not found at %s", koralc))
	}

	code, out := runCmd(root, koralc, "build", "fmt/koralfmt.koral", "-o", "bin")
	if code != 0 {
		fatal(fmt.Errorf("build koralfmt failed (exit=%d)\n%s", code, out))
	}

	if _, err := os.Stat(fmtExe); err != nil {
		fatal(fmt.Errorf("koralfmt binary not found at %s", fmtExe))
	}

	fmt.Printf("koralfmt prepared: %s\n", fmtExe)
}

func findRepoRoot() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("getwd failed: %w", err)
	}

	cur := wd
	for {
		marker := filepath.Join(cur, "fmt", "koralfmt.koral")
		if _, err := os.Stat(marker); err == nil {
			return cur, nil
		}
		next := filepath.Dir(cur)
		if next == cur {
			return "", fmt.Errorf("repo root not found from %s", wd)
		}
		cur = next
	}
}

func runCmd(cwd string, exe string, args ...string) (int, string) {
	cmd := exec.Command(exe, args...)
	cmd.Dir = cwd
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	if err == nil {
		return 0, normalizeText(buf.String())
	}
	if exitErr, ok := err.(*exec.ExitError); ok {
		return exitErr.ExitCode(), normalizeText(buf.String())
	}
	return -1, fmt.Sprintf("run failed: %v\n%s", err, normalizeText(buf.String()))
}

func normalizeText(s string) string {
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = strings.ReplaceAll(s, "\r", "\n")
	lines := strings.Split(s, "\n")
	for i, line := range lines {
		lines[i] = strings.TrimRight(line, " \t")
	}
	out := strings.Join(lines, "\n")
	out = strings.TrimRight(out, "\n")
	return out
}

func exeName(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}
	return name
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err.Error())
	os.Exit(1)
}
