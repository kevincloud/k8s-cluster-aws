#!/bin/bash

echo "Pre-installation tasks..."

# 
# Install OS updates
# 
echo 'libc6 libraries/restart-without-asking boolean true' | sudo debconf-set-selections
echo 'grub-pc grub-pc/install_devices_empty boolean true' | sudo debconf-set-selections
echo 'grub-pc grub-pc/linux_cmdline seen true' | sudo debconf-set-selections
export DEBIAN_FRONTEND=noninteractive
echo "...installing Ubuntu updates"

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

sudo apt-get -y update
sudo apt-get -y upgrade

sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    python3-pip \
    software-properties-common \
    docker-ce=5:18.09.0~3-0~ubuntu-bionic \
    kubelet \
    kubeadm \
    kubectl

pip3 install Flask
pip3 install awscli

export CLIENT_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`

echo "k8s-master" > /etc/hostname
echo "$CLIENT_IP k8s-master" >> /etc/hosts
hostnamectl set-hostname k8s-master

kubeadm init --apiserver-advertise-address=$CLIENT_IP > /root/init.txt

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

cat /root/init.txt | tail -2 > /root/kubeadm-join.txt

export KUBEJOIN="$(cat /root/kubeadm-join.txt | sed -e ':a;N;$!ba;s/ \\\n    / /g')"
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.profile

mkdir -p /etc/cni/net.d
mkdir -p /opt/cni/bin
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.6/config/v1.6/aws-k8s-cni.yaml

while [[ ! -z $(kubectl get pods --all-namespaces | sed -n '/Running/ !p' | sed -n '/NAMESPACE/ !p') ]]; do
    sleep 1
done

sudo bash -c "cat >/root/ready.py" <<EOT
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "$KUBEJOIN"

if __name__ == '__main__':
    app.run(host='0.0.0.0')
EOT

python3 /root/ready.py &
