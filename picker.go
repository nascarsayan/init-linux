package main

import (
	"fmt"
	"os"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	accentStyle = lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "#8839ef", Dark: "#c6a0f6"})
	mutedStyle  = lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "#6c6f85", Dark: "#939ab7"})
	okStyle     = lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "#40a02b", Dark: "#a6da95"})
	titleStyle  = accentStyle.Bold(true)
)

type pickerRow struct {
	group string
	tool  *tool
}

type picker struct {
	rows      []pickerRow
	on        map[string]bool
	cursor    int
	offset    int
	height    int
	done      bool
	cancelled bool
}

func newPicker(selected []string) *picker {
	groups := map[string][]tool{}
	for _, item := range catalog {
		groups[item.Group] = append(groups[item.Group], item)
	}
	names := make([]string, 0, len(groups))
	for name := range groups {
		names = append(names, name)
	}
	sort.Strings(names)

	var rows []pickerRow
	for _, group := range names {
		rows = append(rows, pickerRow{group: group})
		items := groups[group]
		for i := range items {
			rows = append(rows, pickerRow{group: group, tool: &items[i]})
		}
	}
	on := make(map[string]bool, len(selected))
	for _, name := range selected {
		on[name] = true
	}
	p := &picker{rows: rows, on: on, height: 24}
	if len(rows) > 1 {
		p.cursor = 1
	}
	return p
}

func (p *picker) Init() tea.Cmd { return nil }

func (p *picker) visibleRows() int { return max(1, p.height-5) }

func (p *picker) syncViewport() {
	visible := p.visibleRows()
	if p.cursor < p.offset {
		p.offset = p.cursor
	}
	if p.cursor >= p.offset+visible {
		p.offset = p.cursor - visible + 1
	}
	p.offset = min(p.offset, max(0, len(p.rows)-visible))
}

func (p *picker) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		if msg.Height > 0 {
			p.height = msg.Height
		}
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			p.cursor = max(0, p.cursor-1)
		case "down", "j":
			p.cursor = min(len(p.rows)-1, p.cursor+1)
		case "pgup":
			p.cursor = max(0, p.cursor-p.visibleRows())
		case "pgdown":
			p.cursor = min(len(p.rows)-1, p.cursor+p.visibleRows())
		case " ", "x":
			p.toggle()
		case "a":
			p.setAll(true)
		case "n":
			p.setAll(false)
		case "enter":
			p.done = true
			return p, tea.Quit
		case "q", "esc", "ctrl+c":
			p.cancelled = true
			return p, tea.Quit
		}
	}
	p.syncViewport()
	return p, nil
}

func (p *picker) toolsIn(group string) []string {
	var names []string
	for _, row := range p.rows {
		if row.group == group && row.tool != nil {
			names = append(names, row.tool.Name)
		}
	}
	return names
}

func (p *picker) toggle() {
	row := p.rows[p.cursor]
	if row.tool != nil {
		p.on[row.tool.Name] = !p.on[row.tool.Name]
		return
	}
	all := true
	for _, name := range p.toolsIn(row.group) {
		all = all && p.on[name]
	}
	for _, name := range p.toolsIn(row.group) {
		p.on[name] = !all
	}
}

func (p *picker) setAll(value bool) {
	for _, row := range p.rows {
		if row.tool != nil {
			p.on[row.tool.Name] = value
		}
	}
}

func (p *picker) groupMark(group string) string {
	names := p.toolsIn(group)
	n := 0
	for _, name := range names {
		if p.on[name] {
			n++
		}
	}
	switch {
	case n == 0:
		return "[ ]"
	case n == len(names):
		return okStyle.Render("[x]")
	default:
		return okStyle.Render("[~]")
	}
}

func (p *picker) View() string {
	if p.done || p.cancelled {
		return ""
	}
	var b strings.Builder
	b.WriteString(titleStyle.Render("what to install") + "\n")
	b.WriteString(mutedStyle.Render("space toggle · a all · n none · enter confirm · q cancel") + "\n\n")
	end := min(len(p.rows), p.offset+p.visibleRows())
	for i := p.offset; i < end; i++ {
		row := p.rows[i]
		pointer := "  "
		if i == p.cursor {
			pointer = accentStyle.Render("❯ ")
		}
		if row.tool == nil {
			name := row.group
			if i == p.cursor {
				name = accentStyle.Bold(true).Render(name)
			}
			fmt.Fprintf(&b, "%s%s %s\n", pointer, p.groupMark(row.group), name)
			continue
		}
		mark := "[ ]"
		if p.on[row.tool.Name] {
			mark = okStyle.Render("[x]")
		}
		name := fmt.Sprintf("%-14s", row.tool.Name)
		if i == p.cursor {
			name = accentStyle.Bold(true).Render(row.tool.Name) + strings.Repeat(" ", max(0, 14-len(row.tool.Name)))
		}
		fmt.Fprintf(&b, "    %s%s %s %s\n", pointer, mark, name, mutedStyle.Render(row.tool.Size))
	}
	fmt.Fprintf(&b, "\n%s", mutedStyle.Render(p.footer()))
	return b.String()
}

func (p *picker) footer() string {
	selected := p.selected()
	return fmt.Sprintf("%d selected · rows %d–%d of %d", len(selected), p.offset+1,
		min(len(p.rows), p.offset+p.visibleRows()), len(p.rows))
}

func (p *picker) selected() []string {
	var names []string
	for _, item := range catalog {
		if p.on[item.Name] {
			names = append(names, item.Name)
		}
	}
	return names
}

func pickTools(selected []string) ([]string, error) {
	p := newPicker(selected)
	program := tea.NewProgram(p, tea.WithInput(os.Stdin), tea.WithOutput(os.Stderr))
	if _, err := program.Run(); err != nil {
		return nil, err
	}
	if p.cancelled {
		return nil, fmt.Errorf("selection cancelled")
	}
	return p.selected(), nil
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
