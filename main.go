package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

const version = "dev"

type options struct {
	Yes        bool
	DryRun     bool
	Tools      []string
	GhqRoot    string
	ConfigRepo string
	ConfigRef  string
}

func main() {
	if err := runCLI(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "init-sh:", err)
		os.Exit(1)
	}
}

func runCLI(args []string) error {
	if len(args) > 0 && args[0] == "version" {
		fmt.Println(version)
		return nil
	}
	if len(args) > 0 && args[0] == "install" {
		args = args[1:]
	}

	flags := flag.NewFlagSet("init-sh install", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	var rawTools string
	opts := options{}
	flags.BoolVar(&opts.Yes, "yes", false, "use the default tool selection")
	flags.BoolVar(&opts.DryRun, "dry-run", false, "print commands without changing the host")
	flags.StringVar(&rawTools, "tools", "", "comma-separated tool names")
	flags.StringVar(&opts.GhqRoot, "ghq-root", "", "override the platform ghq root")
	flags.StringVar(&opts.ConfigRepo, "config-repo", "https://github.com/nascarsayan/box-config.git", "configuration repository")
	flags.StringVar(&opts.ConfigRef, "config-ref", "main", "configuration branch or tag")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected arguments: %s", strings.Join(flags.Args(), " "))
	}

	if rawTools != "" {
		for _, name := range strings.Split(rawTools, ",") {
			name = strings.TrimSpace(name)
			if name != "" {
				opts.Tools = append(opts.Tools, name)
			}
		}
		if err := validateTools(opts.Tools); err != nil {
			return err
		}
	} else if opts.Yes || !stdinTTY() {
		opts.Tools = defaultTools()
	} else {
		selected, err := pickTools(defaultTools())
		if err != nil {
			return err
		}
		opts.Tools = selected
	}
	return install(opts)
}

func validateTools(names []string) error {
	known := map[string]bool{}
	for _, item := range catalog {
		known[item.Name] = true
	}
	for _, name := range names {
		if !known[name] {
			return fmt.Errorf("unknown tool %q", name)
		}
	}
	return nil
}

func stdinTTY() bool {
	info, err := os.Stdin.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}
