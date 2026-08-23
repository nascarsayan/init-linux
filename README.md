# init-sh

`init-sh` installs a personal command-line environment on macOS and Linux.
It uses one Go binary for selection, package installation, and configuration.

## Install

### Host mode

Host mode installs tools into the normal host environment.
It does not create a Nix sandbox.

```sh
curl -fsSL https://raw.githubusercontent.com/nascarsayan/init-sh/master/install.sh | sh -s -- --machine
```

The macOS path uses Homebrew. The Linux path uses the system package manager for
`git`, `zsh`, and required archive tools. It uses mise for the selected CLI tools.

Linux mise installations belong to the current user. They are host installations,
but they are not available to every account on the machine.

### Sandboxed mode

Sandboxed mode delegates to [`box`](https://github.com/nascarsayan/box).
`box` uses Nix and does not change the host package set.

```sh
curl -fsSL https://raw.githubusercontent.com/nascarsayan/init-sh/master/install.sh | sh -s -- --sandboxed
```

### Noninteractive host install

Use the default selection:

```sh
curl -fsSL https://raw.githubusercontent.com/nascarsayan/init-sh/master/install.sh | sh -s -- --machine --yes
```

Select an exact set:

```sh
curl -fsSL https://raw.githubusercontent.com/nascarsayan/init-sh/master/install.sh | sh -s -- --machine --tools=fzf,ghq,gwq,helix
```

## Installation model

The bootstrap performs these operations:

1. It installs Homebrew on macOS, or mise on Linux.
2. It installs `minijinja-cli`.
3. It downloads a released `init-sh` binary.
4. If no release exists, it builds the binary from the `master` branch.
5. The binary installs the selected tools.
6. The binary renders the shell configuration.

The personal templates are in
[`nascarsayan/box-config/portable`](https://github.com/nascarsayan/box-config/tree/main/portable).
This repository contains installer code only.

The generated files are:

- `~/.zshrc`
- `~/.zshenv`
- `~/.config/gwq/config.toml`
- `~/.config/init-sh/p10k.zsh`

`init-sh` creates one `.pre-init-sh` backup before it replaces an existing shell file.
It keeps zinit for fast deferred plugin loading.

## ghq roots

The default roots are:

- Linux: `~/ws`
- macOS: `~/Code/ghq`

Use `--ghq-root PATH` to replace the default.

## glibc

The current Rocky Linux host has glibc 2.34. This version runs mise, but the
MiniJinja 2.24 GNU binary requires a newer glibc.

The official MiniJinja installer detects this case and selects its static musl
binary. You do not need to install a musl runtime or musl system packages.

## Development

```sh
go test ./...
go build ./...
```

Print the host plan without changes:

```sh
go run . install --dry-run --yes --tools=fzf,ghq
```
