#!/bin/bash

echo "Pre-installation tasks..."

# 
# Install OS updates
# 
echo 'libc6 libraries/restart-without-asking boolean true' | sudo debconf-set-selections
# sudo apt-get remove -y grub
# sudo apt-get install -y grub
export DEBIAN_FRONTEND=noninteractive
echo "...installing Ubuntu updates"
sudo apt-get -y update
# sudo apt-get -y upgrade
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"
sudo apt-get -y update
sudo apt-get install -y docker-ce=5:18.09.0~3-0~ubuntu-bionic

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

export CLIENT_IP=`curl http://169.254.169.254/latest/meta-data/local-ipv4`
export AWS_HOSTNAME=`curl -s http://169.254.169.254/latest/meta-data/local-hostname`

echo $AWS_HOSTNAME > /etc/hostname
hostnamectl set-hostname $AWS_HOSTNAME

curl -s http://10.0.1.10:5000/ > /root/ready.sh
while [ ! -s "/root/ready.sh" ]; do
    sleep 1
    curl -s http://10.0.1.10:5000/ > /root/ready.sh
done
chmod +x /root/ready.sh
. /root/ready.sh
