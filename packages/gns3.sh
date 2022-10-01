install_gns3() {
  sudo add-apt-repository -y ppa:gns3/ppa
  sudo apt update                                
  sudo apt install -y gns3-gui gns3-server
  sudo dpkg --add-architecture i386
  sudo apt update
  sudo apt install gns3-iou -y
}

install_docker() {
  sudo apt remove docker docker-engine docker.io
  sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  sudo apt update
  sudo apt install -y docker-ce
}

add_user_to_groups() {
  for group in ubridge libvirt kvm wireshark docker;
  do
    sudo usermod -aG $group $USER
  done
}

install_gns3
install_docker
add_user_to_groups
