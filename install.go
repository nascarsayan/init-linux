package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

var hostOS = runtime.GOOS

type commandRunner struct {
	dryRun bool
}

func (r commandRunner) run(name string, args ...string) error {
	fmt.Fprintln(os.Stderr, "+", shellCommand(name, args...))
	if r.dryRun {
		return nil
	}
	cmd := exec.Command(name, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func (r commandRunner) output(name string, args ...string) (string, error) {
	if r.dryRun {
		return "", nil
	}
	out, err := exec.Command(name, args...).Output()
	return strings.TrimSpace(string(out)), err
}

func shellCommand(name string, args ...string) string {
	parts := append([]string{name}, args...)
	for i, part := range parts {
		if strings.ContainsAny(part, " \t\n'\"") {
			parts[i] = "'" + strings.ReplaceAll(part, "'", "'\\''") + "'"
		}
	}
	return strings.Join(parts, " ")
}

func defaultGhqRoot(home, platform string) string {
	if platform == "darwin" {
		return filepath.Join(home, "Code", "ghq")
	}
	return filepath.Join(home, "ws")
}
func install(opts options) error {
	if hostOS != "linux" && hostOS != "darwin" {
		return fmt.Errorf("unsupported operating system %q", hostOS)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("find home directory: %w", err)
	}
	if opts.GhqRoot == "" {
		opts.GhqRoot = defaultGhqRoot(home, hostOS)
	}

	runner := commandRunner{dryRun: opts.DryRun}
	if err := requireCommands(opts.DryRun); err != nil {
		return err
	}
	if err := installTools(runner, opts.Tools); err != nil {
		return err
	}

	configHome := os.Getenv("XDG_CONFIG_HOME")
	if configHome == "" {
		configHome = filepath.Join(home, ".config")
	}
	cacheHome := os.Getenv("XDG_CACHE_HOME")
	if cacheHome == "" {
		cacheHome = filepath.Join(home, ".cache")
	}
	configDir := filepath.Join(configHome, "init-sh")
	sourceDir := filepath.Join(cacheHome, "init-sh", "box-config")
	if err := syncRepo(runner, opts.ConfigRepo, opts.ConfigRef, sourceDir); err != nil {
		return fmt.Errorf("get configuration: %w", err)
	}
	if err := installZinit(runner, home); err != nil {
		return fmt.Errorf("install zinit: %w", err)
	}
	if opts.DryRun {
		printRenderPlan(home, configDir, sourceDir, opts.GhqRoot)
		return nil
	}

	brewPrefix := ""
	if hostOS == "darwin" {
		brewPrefix, err = runner.output("brew", "--prefix")
		if err != nil {
			return fmt.Errorf("get Homebrew prefix: %w", err)
		}
	}
	contextPath, err := writeContext(configDir, map[string]string{
		"brew_prefix": brewPrefix,
		"ghq_root":    opts.GhqRoot,
	})
	if err != nil {
		return err
	}
	if err := renderFile(filepath.Join(sourceDir, "portable", "zshrc.zsh.j2"), contextPath, filepath.Join(home, ".zshrc")); err != nil {
		return err
	}
	if err := renderFile(filepath.Join(sourceDir, "portable", "zshenv.zsh.j2"), contextPath, filepath.Join(home, ".zshenv")); err != nil {
		return err
	}
	if err := renderFile(filepath.Join(sourceDir, "portable", "gwq.toml.j2"), contextPath, filepath.Join(configHome, "gwq", "config.toml")); err != nil {
		return err
	}
	if err := copyFile(filepath.Join(sourceDir, "zsh", "p10k.zsh"), filepath.Join(configDir, "p10k.zsh")); err != nil {
		return fmt.Errorf("install p10k configuration: %w", err)
	}
	if err := os.MkdirAll(opts.GhqRoot, 0o755); err != nil {
		return fmt.Errorf("create ghq root: %w", err)
	}
	if err := runner.run("git", "config", "--global", "ghq.root", opts.GhqRoot); err != nil {
		return fmt.Errorf("configure ghq root: %w", err)
	}

	fmt.Fprintf(os.Stderr, "installed %d tools and rendered shell configuration\n", len(opts.Tools))
	fmt.Fprintln(os.Stderr, "start zsh with: exec zsh")
	return nil
}

func requireCommands(dryRun bool) error {
	if dryRun {
		return nil
	}
	required := []string{"git", "zsh", "minijinja-cli"}
	if hostOS == "darwin" {
		required = append(required, "brew")
	} else {
		required = append(required, "mise")
	}
	for _, name := range required {
		if _, err := exec.LookPath(name); err != nil {
			return fmt.Errorf("required command %q is missing; run install.sh first", name)
		}
	}
	return nil
}

func installTools(runner commandRunner, selected []string) error {
	byName := map[string]tool{}
	for _, item := range catalog {
		byName[item.Name] = item
	}
	args := []string{"install"}
	if hostOS == "linux" {
		args = []string{"use", "--global"}
	}
	for _, name := range selected {
		item, ok := byName[name]
		if !ok {
			return fmt.Errorf("unknown tool %q", name)
		}
		provider := item.Brew
		if hostOS == "linux" {
			provider = item.Mise + "@latest"
		}
		args = append(args, provider)
	}
	if len(selected) == 0 {
		return nil
	}
	command := "brew"
	if hostOS == "linux" {
		command = "mise"
	}
	if err := runner.run(command, args...); err != nil {
		return fmt.Errorf("install tools with %s: %w", command, err)
	}
	return nil
}

func syncRepo(runner commandRunner, repo, ref, destination string) error {
	if _, err := os.Stat(filepath.Join(destination, ".git")); err == nil {
		if err := runner.run("git", "-C", destination, "fetch", "--depth", "1", "origin", ref); err != nil {
			return err
		}
		return runner.run("git", "-C", destination, "checkout", "--detach", "FETCH_HEAD")
	}
	if _, err := os.Stat(destination); err == nil && !runner.dryRun {
		return fmt.Errorf("%s exists but is not a Git repository", destination)
	}
	if !runner.dryRun {
		if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
			return err
		}
	}
	return runner.run("git", "clone", "--depth", "1", "--branch", ref, repo, destination)
}

func installZinit(runner commandRunner, home string) error {
	dataHome := os.Getenv("XDG_DATA_HOME")
	if dataHome == "" {
		dataHome = filepath.Join(home, ".local", "share")
	}
	destination := filepath.Join(dataHome, "zinit", "zinit.git")
	if _, err := os.Stat(filepath.Join(destination, ".git")); err == nil {
		return runner.run("git", "-C", destination, "pull", "--ff-only")
	}
	if !runner.dryRun {
		if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
			return err
		}
	}
	return runner.run("git", "clone", "--depth", "1", "https://github.com/zdharma-continuum/zinit.git", destination)
}

func writeContext(configDir string, values map[string]string) (string, error) {
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		return "", fmt.Errorf("create configuration directory: %w", err)
	}
	path := filepath.Join(configDir, "context.json")
	data, err := json.MarshalIndent(values, "", "  ")
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(path, append(data, '\n'), 0o600); err != nil {
		return "", fmt.Errorf("write template context: %w", err)
	}
	return path, nil
}

func renderFile(template, context, destination string) error {
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	temporary := destination + ".new"
	file, err := os.OpenFile(temporary, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	cmd := exec.Command("minijinja-cli", template, context)
	cmd.Stdout = file
	cmd.Stderr = os.Stderr
	runErr := cmd.Run()
	closeErr := file.Close()
	if runErr != nil {
		os.Remove(temporary)
		return fmt.Errorf("render %s: %w", template, runErr)
	}
	if closeErr != nil {
		os.Remove(temporary)
		return closeErr
	}
	if err := backupOnce(destination); err != nil {
		return err
	}
	if err := os.Rename(temporary, destination); err != nil {
		return fmt.Errorf("install %s: %w", destination, err)
	}
	return nil
}

func backupOnce(path string) error {
	if _, err := os.Stat(path); err != nil {
		return nil
	}
	backup := path + ".pre-init-sh"
	if _, err := os.Stat(backup); err == nil {
		return nil
	}
	if err := copyFile(path, backup); err != nil {
		return fmt.Errorf("back up %s: %w", path, err)
	}
	return nil
}

func copyFile(source, destination string) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	temporary := destination + ".new"
	output, err := os.OpenFile(temporary, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(output, input)
	closeErr := output.Close()
	if copyErr != nil {
		os.Remove(temporary)
		return copyErr
	}
	if closeErr != nil {
		os.Remove(temporary)
		return closeErr
	}
	return os.Rename(temporary, destination)
}

func printRenderPlan(home, configDir, sourceDir, ghqRoot string) {
	context := filepath.Join(configDir, "context.json")
	fmt.Fprintln(os.Stderr, "+ write", context)
	fmt.Fprintln(os.Stderr, "+ minijinja-cli", filepath.Join(sourceDir, "portable", "zshrc.zsh.j2"), context, ">", filepath.Join(home, ".zshrc"))
	fmt.Fprintln(os.Stderr, "+ minijinja-cli", filepath.Join(sourceDir, "portable", "zshenv.zsh.j2"), context, ">", filepath.Join(home, ".zshenv"))
	fmt.Fprintln(os.Stderr, "+ minijinja-cli", filepath.Join(sourceDir, "portable", "gwq.toml.j2"), context, ">", filepath.Join(configDir, "..", "gwq", "config.toml"))
	fmt.Fprintln(os.Stderr, "+ git config --global ghq.root", ghqRoot)
}
