#!/usr/bin/env bash
sudo apt-get install -y curl git mercurial make binutils bison gcc build-essential
zsh < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)

printf "gvm installed. Now installed some version of go:\n\
exec -l \$SHELL\n\
gvm listall\n\
gvm install go1.18.3 -B\n\
gvm use 1.18.3 --default\n\
"
