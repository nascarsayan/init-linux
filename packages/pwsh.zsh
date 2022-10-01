# * Powershell

ubuntu_ver=$(cut -f2 <<< $(lsb_release -r))

# Download the Microsoft repository GPG keys
wget -q "https://packages.microsoft.com/config/ubuntu/${ubuntu_ver}/packages-microsoft-prod.deb"

# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb

rm packages-microsoft-prod.deb

# Update the list of products
sudo apt update

# Enable the "universe" repositories
sudo add-apt-repository universe

cd /usr/lib/x86_64-linux-gnu
[ ! -f libssl.so.1.0.0 ] && sudo ln -s libssl.so.1.1 libssl.so.1.0.0
[ ! -f libcrypto.so.1.0.0 ] && sudo ln -s libcrypto.so.1.1 libcrypto.so.1.0.0
cd -

# Install PowerShell and ntlm
sudo apt install -y powershell gss-ntlmssp netbase inetutils-ping
