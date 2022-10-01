#!/usr/bin/env bash

create_user() {
  USERNAME="arcvmware"
  sudo useradd $USERNAME -G sudo
  sudo mkdir /home/$USERNAME
  sudo chown $USERNAME /home/$USERNAME
}

dnf -y install git zsh
