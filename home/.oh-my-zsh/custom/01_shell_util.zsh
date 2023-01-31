# fasd
eval "$(fasd --init auto)"

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# p10k
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# disable bell and beep
unsetopt beep

# tmux on login
tmux_on_login() {
  if [[ -n "$PS1" ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_CONNECTION" ]] && [[ ! $(command -v code 2>/dev/null) ]]; then
    tmux attach-session -t ssh_tmux || tmux new-session -s ssh_tmux
  fi
}

# tmux_on_login
