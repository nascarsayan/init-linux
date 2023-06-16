#!/usr/bin/env bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
sudo rm -rf /var/lib/dpkg/lock* /var/cache/apt/archives/lock
sudo -E apt autoremove -y --purge unattended-upgrades
sudo -E apt update
sudo -E apt install nnn
# sudo -E apt upgrade -y
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
chmod u+x nvim.appimage
./nvim.appimage --appimage-extract
sudo mv squashfs-root /
sudo ln -s /squashfs-root/AppRun /usr/bin/nvim
sudo -E apt install build-essential net-tools vim git zsh tmux fasd tree jq htop curl wget netplan.io nano iputils-ping mercurial bison bat -y
sudo wget https://github.com/mikefarah/yq/releases/download/v4.13.3/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
# wget https://arcscvmm.blob.core.windows.net/temp/cc-arcvmm.sh -O packages/cc-arcvmm.sh
curl -L https://git.io/n-install | bash -s -- -y

# * Zsh setup
# install oh my zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
if [ ! -f "$HOME/.zshrc" ]; then
  echo "oh-my-zsh could not be cloned. Please try again."
  return
fi

zsh_custom=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
# install zsh autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions "$zsh_custom/plugins/zsh-autosuggestions"

# install zsh syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$zsh_custom/plugins/zsh-syntax-highlighting"

# install kubectl aliases
wget https://raw.githubusercontent.com/ahmetb/kubectl-alias/master/.kubectl_aliases -O "$zsh_custom/20_kubectl.zsh"

# install p10k
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$zsh_custom/themes/powerlevel10k"

# installspaceship prompt
git clone https://github.com/denysdovhan/spaceship-prompt.git "$zsh_custom/themes/spaceship-prompt" --depth=1
ln -s "$zsh_custom/themes/spaceship-prompt/spaceship.zsh-theme" "$zsh_custom/themes/spaceship.zsh-theme"

# github theme
wget https://raw.githubusercontent.com/Debdut/github.zsh-theme/main/github.zsh-theme -O "$zsh_custom/themes/github.zsh-theme"

perl -i -pe 's~robbyrussell~github~' "$HOME"/.zshrc
perl -i -pe "s~#\s*(?=DISABLE_MAGIC_FUNCTIONS)~~" "$HOME"/.zshrc
perl -i -pe "s~#\s*(?=DISABLE_UPDATE_PROMPT)~~" "$HOME"/.zshrc
perl -i -pe "s~# (?=(zstyle ':omz:update' mode auto))~~" "$HOME"/.zshrc
plugins="\n  git\n  zsh-syntax-highlighting\n  dircycle\n  urltools\n  zsh-autosuggestions\n  sudo\n  vscode\n  fasd\n  colored-man-pages\n  git-extras\n  kubectl\n  docker  \n  docker-compose helm\n"
perl -i -pe "s~(?<=plugins=\()git(?=\))~$plugins~" "$HOME"/.zshrc
perl -i -pe "s~^source~autoload -U +X bashcompinit && bashcompinit\n\nsource~" "$HOME"/.zshrc

# install fzf
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --all

echo "Configuring tmux"
git clone https://github.com/gpakosz/.tmux.git ~/.tmux
ln -s -f ~/.tmux/.tmux.conf ~/.tmux.conf
git clone https://github.com/nascarsayan/.tmux.local.git ~/.tmux.local
ln -s -f ~/.tmux.local/.tmux.conf.local ~/.tmux.conf.local

# Tell the patches to make
echo "
## Have made the following changes:

ZSH_THEME=\"spaceship\"

plugins=(
  git
  zsh-syntax-highlighting
  dircycle
  urltools
  zsh-autosuggestions
  sudo
  vscode
  fasd
  colored-man-pages
  git-extras
  kubectl
  helm
)

autoload -U +X bashcompinit && bashcompinit

DISABLE_MAGIC_FUNCTIONS=true
DISABLE_UPDATE_PROMPT=true
"

# * Copy customizations
chmod 0700 "$SCRIPT_DIR/home/.ssh"
find "$SCRIPT_DIR/home/.ssh" -not -name "*.pub" -name "id_rsa*" -exec chmod 0600 "{}" "+"

rsync -a "$SCRIPT_DIR/home/" ~
perl -i -pe "s/uname/$USER/" ~/.gitconfig

echo "Changing the default shell to zsh"
sudo chsh -s "$(which zsh)" "$USER"
