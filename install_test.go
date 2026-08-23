package main

import (
	"path/filepath"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestPlatformGhqRoots(t *testing.T) {
	home := filepath.Join(string(filepath.Separator), "home", "sayan")
	if got := defaultGhqRoot(home, "linux"); got != filepath.Join(home, "ws") {
		t.Fatalf("Linux ghq root = %q", got)
	}
	if got := defaultGhqRoot(home, "darwin"); got != filepath.Join(home, "Code", "ghq") {
		t.Fatalf("macOS ghq root = %q", got)
	}
}

func TestGwqUsesUpstreamHomebrewTap(t *testing.T) {
	for _, item := range catalog {
		if item.Name == "gwq" {
			if item.Brew != "d-kuro/tap/gwq" {
				t.Fatalf("gwq Homebrew formula = %q", item.Brew)
			}
			return
		}
	}
	t.Fatal("gwq is missing from the catalog")
}

func TestUnknownToolFailsBeforeInstallation(t *testing.T) {
	err := validateTools([]string{"not-a-tool"})
	if err == nil || !strings.Contains(err.Error(), "not-a-tool") {
		t.Fatalf("unknown tool error = %v", err)
	}
}

func TestPickerViewportFollowsCursor(t *testing.T) {
	p := newPicker(defaultTools())
	p.Update(tea.WindowSizeMsg{Width: 80, Height: 8})
	for range p.rows {
		p.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("j")})
	}
	if p.cursor != len(p.rows)-1 {
		t.Fatalf("cursor = %d, want %d", p.cursor, len(p.rows)-1)
	}
	if p.offset == 0 || p.cursor >= p.offset+p.visibleRows() {
		t.Fatalf("cursor %d is outside viewport [%d,%d)", p.cursor, p.offset, p.offset+p.visibleRows())
	}
	if lines := strings.Count(p.View(), "\n") + 1; lines > p.height {
		t.Fatalf("view uses %d lines in a %d-line terminal", lines, p.height)
	}
	for range p.rows {
		p.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("k")})
	}
	if p.cursor != 0 || p.offset != 0 {
		t.Fatalf("up did not restore first viewport: cursor=%d offset=%d", p.cursor, p.offset)
	}
}

func TestDryRunDoesNotWriteHome(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_CACHE_HOME", filepath.Join(home, ".cache"))
	oldOS := hostOS
	hostOS = "linux"
	t.Cleanup(func() { hostOS = oldOS })

	if err := install(options{DryRun: true, Yes: true, Tools: []string{"fzf"}}); err != nil {
		t.Fatal(err)
	}
	if matches, err := filepath.Glob(filepath.Join(home, ".*")); err != nil || len(matches) != 0 {
		t.Fatalf("dry-run changed home: matches=%v err=%v", matches, err)
	}
}
