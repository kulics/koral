package fmttest

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestFmtCaseValidSimple(t *testing.T) {
	runFmtCase(t, "valid_simple")
}

func TestFmtCaseValidGivenWhen(t *testing.T) {
	runFmtCase(t, "valid_given_when")
}

func TestFmtCaseInvalidMissingThen(t *testing.T) {
	runFmtCase(t, "invalid_missing_then")
}

func runFmtCase(t *testing.T, name string) {
	root := findRepoRoot(t)
	requireKoralfmtBuilt(t, root)

	casesDir := filepath.Join(root, "fmt", "test", "cases")
	src := filepath.Join(casesDir, name+".koral")
	expected := filepath.Join(casesDir, name+".expected")
	expectedErr := filepath.Join(casesDir, name+".error")

	_, hasSrc := statOK(src)
	if !hasSrc {
		t.Fatalf("case source not found: %s", src)
	}

	_, hasExpected := statOK(expected)
	_, hasErr := statOK(expectedErr)

	if hasExpected && hasErr {
		t.Fatalf("case %s has both .expected and .error", name)
	}
	if !hasExpected && !hasErr {
		t.Fatalf("case %s must provide either .expected or .error", name)
	}

	tempDir := t.TempDir()
	workFile := filepath.Join(tempDir, filepath.Base(src))
	raw, err := os.ReadFile(src)
	if err != nil {
		t.Fatalf("read case source failed: %v", err)
	}
	if err := os.WriteFile(workFile, raw, 0o644); err != nil {
		t.Fatalf("write temp case failed: %v", err)
	}

	fmtExe := filepath.Join(root, "bin", exeName("koralfmt"))
	code, out := runCmd(root, fmtExe, workFile)

	if hasErr {
		if code == 0 {
			t.Fatalf("expected failure, got success")
		}
		wantRaw, err := os.ReadFile(expectedErr)
		if err != nil {
			t.Fatalf("read .error failed: %v", err)
		}
		want := strings.TrimSpace(normalizeText(string(wantRaw)))
		if want != "" && !strings.Contains(normalizeText(out), want) {
			t.Fatalf("expected error substring not found\nwant: %q\nout:\n%s", want, out)
		}
		return
	}

	if code != 0 {
		t.Fatalf("expected success, got exit=%d\nout:\n%s", code, out)
	}

	gotRaw, err := os.ReadFile(workFile)
	if err != nil {
		t.Fatalf("read formatted output failed: %v", err)
	}
	wantRaw, err := os.ReadFile(expected)
	if err != nil {
		t.Fatalf("read expected failed: %v", err)
	}

	got := normalizeText(string(gotRaw))
	want := normalizeText(string(wantRaw))
	if got != want {
		t.Fatalf("formatted output mismatch\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
}

func findRepoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd failed: %v", err)
	}
	cur := wd
	for {
		marker := filepath.Join(cur, "fmt", "koralfmt.koral")
		if _, ok := statOK(marker); ok {
			return cur
		}
		next := filepath.Dir(cur)
		if next == cur {
			t.Fatalf("repo root not found from %s", wd)
		}
		cur = next
	}
}

func requireKoralfmtBuilt(t *testing.T, root string) {
	t.Helper()
	fmtExe := filepath.Join(root, "bin", exeName("koralfmt"))
	if _, ok := statOK(fmtExe); !ok {
		t.Fatalf("koralfmt binary not found at %s; run `go run ./cmd/preparefmt` from fmt/test first", fmtExe)
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

func statOK(path string) (os.FileInfo, bool) {
	info, err := os.Stat(path)
	if err != nil {
		return nil, false
	}
	return info, true
}

func exeName(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}
	return name
}
