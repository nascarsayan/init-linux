#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Install base packages and tools
install_packages() {
  echo "Installing base packages..."
  brew_packages=(nnn vim git zsh tmux tree jq htop curl wget nano iputils bison bat neovim tmux)
  
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v brew &> /dev/null; then
      echo "Homebrew is not installed. Please install Homebrew first."
      exit 1
    fi
    brew install "${brew_packages[@]}"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v brew &> /dev/null; then
      brew install "${brew_packages[@]}"
    elif command -v apt &> /dev/null; then
      sudo rm -rf /var/lib/dpkg/lock* /var/cache/apt/archives/lock
      sudo -E apt autoremove -y --purge unattended-upgrades
      sudo -E apt update
      sudo -E apt install -y nnn build-essential net-tools vim git zsh tmux fasd tree jq htop curl wget nano iputils-ping mercurial bison bat

      # Install neovim
      curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
      chmod u+x nvim.appimage
      ./nvim.appimage --appimage-extract > /dev/null 2>&1
      sudo mv squashfs-root /
      sudo ln -s /squashfs-root/AppRun /usr/bin/nvim
    else
      echo "Neither Homebrew nor apt is installed. Please install one of them first to install the initial packages"
      exit 1
    fi
  else
    echo "Unsupported OS type: $OSTYPE"
    exit 1
  fi
}

# Install additional tools (yq, node)
install_tools() {
  echo "Installing additional tools..."
  
  # Install yq
  sudo curl -L https://github.com/mikefarah/yq/releases/download/v4.13.3/yq_linux_amd64 -o /usr/bin/yq && sudo chmod +x /usr/bin/yq
  
  # Install node via n-install
  curl -L https://git.io/n-install | bash -s -- -y
}

# Configure zsh with zinit
configure_zsh() {
  echo "Configuring zsh with zinit..."
  
  # Clean up any existing oh-my-zsh installation
  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "Removing existing oh-my-zsh installation"
    rm -rf "$HOME/.oh-my-zsh"
  fi

  # Install Zinit
  ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"

  # Create basic .zshrc if it doesn't exist
  if [ ! -f "$HOME/.zshrc" ]; then
    touch "$HOME/.zshrc"
  fi

  # Configure .zshrc for Zinit from template
  if [ -f "$SCRIPT_DIR/templates/zshrc-tpl.zsh" ]; then
    cp "$SCRIPT_DIR/templates/zshrc-tpl.zsh" "$HOME/.zshrc"
  else
    echo "Warning: zshrc-tpl.zsh template not found. Creating basic .zshrc..."
    echo "# Basic zsh configuration - please add your custom settings" > "$HOME/.zshrc"
  fi

  echo "
## Zsh configured with Zinit:

- Installed Zinit plugin manager
- Using Powerlevel10k theme (run 'p10k configure' to customize)
- Loaded plugins: git, sudo, colored-man-pages, kubectl, docker, helm, vscode, git-extras
- Loaded zsh-users plugins: autosuggestions, syntax-highlighting, completions
- Kubectl aliases available
- Settings: DISABLE_MAGIC_FUNCTIONS=true, DISABLE_UPDATE_PROMPT=true
"
}

# Install and configure fzf
install_fzf() {
  echo "Installing fzf..."
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  ~/.fzf/install --all
}

# Configure tmux
configure_tmux() {
  echo "Configuring tmux..."
  git clone https://github.com/gpakosz/.tmux.git ~/.tmux
  ln -s -f ~/.tmux/.tmux.conf ~/.tmux.conf
  git clone https://github.com/nascarsayan/.tmux.local.git ~/.tmux.local
  ln -s -f ~/.tmux.local/.tmux.conf.local ~/.tmux.conf.local
}

# Copy user customizations
copy_customizations() {
  echo "Copying customizations..."
  chmod 0700 "$SCRIPT_DIR/home/.ssh"
  find "$SCRIPT_DIR/home/.ssh" -not -name "*.pub" -name "id_rsa*" -exec chmod 0600 "{}" "+"

  rsync -a "$SCRIPT_DIR/home/" ~
  perl -i -pe "s/uname/$USER/" ~/.gitconfig
}

# Change default shell to zsh
change_shell() {
  echo "Changing the default shell to zsh"
  sudo chsh -s "$(which zsh)" "$USER"
}

# Main function that orchestrates all setup
main() {
  echo "Starting system initialization..."
  
  # install_packages
  # install_tools
  configure_zsh
  install_fzf
  # configure_tmux
  # copy_customizations
  change_shell
  
  echo "
🎉 System initialization completed!

Next steps:
- Restart your shell or run 'exec zsh'
- Run 'p10k configure' to customize your prompt
- Your tmux and other configurations are ready to use
"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi