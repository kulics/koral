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

func TestFmtCases(t *testing.T) {
    root := findRepoRoot(t)
    buildKoralfmt(t, root)

    casesDir := filepath.Join(root, "fmt", "test", "cases")
    entries, err := os.ReadDir(casesDir)
    if err != nil {
        t.Fatalf("read cases dir failed: %v", err)
    }

    for _, e := range entries {
        if e.IsDir() || !strings.HasSuffix(e.Name(), ".koral") {
            continue
        }
        name := strings.TrimSuffix(e.Name(), ".koral")
        src := filepath.Join(casesDir, e.Name())
        expected := filepath.Join(casesDir, name+".expected")
        expectedErr := filepath.Join(casesDir, name+".error")

        _, hasExpected := statOK(expected)
        _, hasErr := statOK(expectedErr)

        t.Run(name, func(t *testing.T) {
            if hasExpected && hasErr {
                t.Fatalf("case %s has both .expected and .error", name)
            }
            if !hasExpected && !hasErr {
                t.Fatalf("case %s must provide either .expected or .error", name)
            }

            tempDir := t.TempDir()
            workFile := filepath.Join(tempDir, e.Name())
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
        })
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

func buildKoralfmt(t *testing.T, root string) {
    t.Helper()
    koralc := filepath.Join(root, "bin", exeName("koralc"))
    if _, ok := statOK(koralc); !ok {
        t.Fatalf("koralc binary not found at %s", koralc)
    }

    code, out := runCmd(root, koralc, "build", "fmt/koralfmt.koral", "-o", "bin")
    if code != 0 {
        t.Fatalf("build koralfmt failed (exit=%d)\n%s", code, out)
    }

    fmtExe := filepath.Join(root, "bin", exeName("koralfmt"))
    if _, ok := statOK(fmtExe); !ok {
        t.Fatalf("koralfmt binary not found at %s", fmtExe)
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
