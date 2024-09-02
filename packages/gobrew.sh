#!/usr/bin/env bash
curl -sL https://raw.githubusercontent.com/kevincobain2000/gobrew/master/git.io.sh | sh
cat <<EOF >> ~/.zshrc
export PATH="\$HOME/.gobrew/current/bin:\$HOME/.gobrew/bin:\$HOME/go/bin:\$PATH"
export GOROOT="\$HOME/.gobrew/current/go"
EOF
export PATH="$HOME/.gobrew/current/bin:$HOME/.gobrew/bin:$HOME/go/bin:$PATH"
export GOROOT="$HOME/.gobrew/current/go"
gobrew
