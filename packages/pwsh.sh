#!/usr/bin/env bash
ubuntu_ver=$(cut -f2 <<< "$(lsb_release -r)")

# Download the Microsoft repository GPG keys
wget -q "https://packages.microsoft.com/config/ubuntu/${ubuntu_ver}/packages-microsoft-prod.deb"

# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb

rm packages-microsoft-prod.deb

# Update the list of products
sudo apt update

# Enable the "universe" repositories
sudo add-apt-repository universe

fol=/usr/lib/x86_64-linux-gnu
[ ! -f $fol/libssl.so.1.0.0 ] && sudo ln -s $fol/libssl.so.1.1 $fol/libssl.so.1.0.0
[ ! -f $fol/libcrypto.so.1.0.0 ] && sudo ln -s $fol/libcrypto.so.1.1 $fol/libcrypto.so.1.0.0

# Install PowerShell and ntlm
sudo apt install -y powershell gss-ntlmssp netbase inetutils-ping
