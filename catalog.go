package main

type tool struct {
	Group   string
	Name    string
	Size    string
	URL     string
	Brew    string
	Mise    string
	Default bool
}

var catalog = []tool{
	{Group: "core", Name: "tmux", Size: "~2M", Brew: "tmux", Mise: "tmux", Default: true},
	{Group: "core", Name: "helix", Size: "~35M", Brew: "helix", Mise: "helix", Default: true},
	{Group: "core", Name: "gh", Size: "~35M", Brew: "gh", Mise: "gh", Default: true},
	{Group: "core", Name: "delta", Size: "~15M", Brew: "git-delta", Mise: "delta", Default: true},
	{Group: "core", Name: "ghq", Size: "~10M", Brew: "ghq", Mise: "ghq", Default: true},
	{Group: "core", Name: "gwq", Size: "~10M", Brew: "gwq", Mise: "ubi:d-kuro/gwq", Default: true},
	{Group: "core", Name: "ripgrep", Size: "~10M", Brew: "ripgrep", Mise: "ripgrep", Default: true},
	{Group: "core", Name: "fd", Size: "~5M", Brew: "fd", Mise: "fd", Default: true},
	{Group: "core", Name: "eza", Size: "~5M", Brew: "eza", Mise: "eza", Default: true},
	{Group: "core", Name: "bat", Size: "~5M", Brew: "bat", Mise: "bat", Default: true},
	{Group: "core", Name: "broot", Size: "~10M", Brew: "broot", Mise: "ubi:Canop/broot", Default: true},
	{Group: "core", Name: "jq", Size: "~2M", Brew: "jq", Mise: "jq", Default: true},
	{Group: "core", Name: "yq", Size: "~10M", Brew: "yq", Mise: "yq", Default: true},
	{Group: "core", Name: "fzf", Size: "~5M", Brew: "fzf", Mise: "fzf", Default: true},
	{Group: "core", Name: "zoxide", Size: "~5M", Brew: "zoxide", Mise: "zoxide", Default: true},
	{Group: "core", Name: "atuin", Size: "~20M", Brew: "atuin", Mise: "atuin", Default: true},

	{Group: "kubernetes", Name: "kubectl", Size: "~55M", Brew: "kubectl", Mise: "kubectl", Default: true},
	{Group: "kubernetes", Name: "kubecolor", Size: "~15M", Brew: "kubecolor", Mise: "kubecolor", Default: true},
	{Group: "kubernetes", Name: "helm", Size: "~80M", Brew: "helm", Mise: "helm", Default: true},
	{Group: "kubernetes", Name: "k9s", Size: "~170M", Brew: "k9s", Mise: "k9s", Default: true},
	{Group: "kubernetes", Name: "kubectx", Size: "~5M", Brew: "kubectx", Mise: "kubectx", Default: true},
	{Group: "kubernetes", Name: "krew", Size: "~10M", Brew: "krew", Mise: "krew", Default: true},
	{Group: "kubernetes", Name: "stern", Size: "~25M", Brew: "stern", Mise: "stern", Default: true},

	{Group: "files", Name: "yazi", Size: "~1.4G", Brew: "yazi", Mise: "yazi"},
	{Group: "files", Name: "duf", Size: "~10M", Brew: "duf", Mise: "duf", Default: true},
	{Group: "network", Name: "xh", Size: "~15M", Brew: "xh", Mise: "xh", Default: true},
	{Group: "network", Name: "croc", Size: "~25M", Brew: "croc", Mise: "croc", Default: true},
	{Group: "network", Name: "jnv", Size: "~10M", Brew: "jnv", Mise: "jnv", Default: true},
	{Group: "monitoring", Name: "btop", Size: "~15M", Brew: "btop", Mise: "btop", Default: true},
	{Group: "multiplexer", Name: "zellij", Size: "~90M", Brew: "zellij", Mise: "zellij"},
	{Group: "ai", Name: "claude-code", Size: "~270M", Brew: "claude-code", Mise: "claude-code"},
	{Group: "ai", Name: "codex", Size: "~490M", Brew: "codex", Mise: "npm:@openai/codex"},
}

func defaultTools() []string {
	var names []string
	for _, item := range catalog {
		if item.Default {
			names = append(names, item.Name)
		}
	}
	return names
}
