#!/usr/bin/env bash
sudo apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
xz-utils tk-dev libffi-dev liblzma-dev python-openssl git

curl https://pyenv.run | bash

printf "pyenv installed. Now installed some version of python:\n\
exec -l \$SHELL\n\
pyenv list\n\
pyenv install 3.10.4\n\
pyenv global 3.10.4\n\
"
