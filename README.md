## Steps:

### 1. Customize 

  - Either add all your keys with prefix `id_rsa` (eg: `id_rsa_github`, `id_rsa_github.pub`) in `home/.ssh/`.<br/>
Alternatively, you can add your keys later, after running the scripts.

  - Edit the [`./home/.ssh/config`](./home/.ssh/config) as per your requirements.<br/>
If you have some jumpbox VMs you can manage the configs here.<br/>
You can also edit your `/etc/hosts` file to give user-friendly names to your Jumpbox IPs.

### 2. Set up your cli prompt and install other utility tools.
```sh
bash init.zsh
```

This will set up zsh with oh-my-zsh. Inside [`~/.oh-my-zsh/custom/`](./home/.oh-my-zsh/custom/) you'll find several utility functions and aliases which are loaded (sourced) into the shell.

### 3. Install `pyenv`, `gvm`, etc.

- [pyenv](https://github.com/pyenv/pyenv): Python Version Manager
- [gvm](https://github.com/moovweb/gvm): Go Version Manager
- [n](https://github.com/tj/n): Nodejs Version Manager.<br/>
  Already installed while running `init.sh`, as it has a low footprint, and installs quickly.

```sh
bash packages/pyenv.sh
bash packages/gvm.sh

# And other packages as required.
```

### 4. Merge zsh history.

You can save your `~/.zsh_history` for later reference. A vital step in improving your CLI experience is having access to all the great CLI commands you've run till now.

A function called `merge_zsh_hist` is created in [`~/.oh-my-zsh/custom/03_abbrev.zsh`](./home/.oh-my-zsh/custom/03_abbrev.zsh)

```sh
merge_zsh_hist <path-to-saved-zsh-history-file>
```
I've checked in my personal zsh history: `./.zsh_history`

### 5. Dark Reader

I use [dark reader](https://darkreader.org/) for dark mode on selected websites.
You can import [the config](./darkreader.json) in any of the supported web browsers to [be kind to your eyes](https://www.youtube.com/watch?v=ofd3xWFtoMY).
