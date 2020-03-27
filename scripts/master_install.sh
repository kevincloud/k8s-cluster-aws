#!/bin/bash

echo "Pre-installation tasks..."

# 
# Install OS updates
# 
echo 'libc6 libraries/restart-without-asking boolean true' | sudo debconf-set-selections
# echo 'grub-pc grub-pc/install_devices_empty boolean true' | sudo debconf-set-selections
# echo 'grub-pc grub-pc/linux_cmdline seen true' | sudo debconf-set-selections
# sudo apt-get remove -y grub-pc
# sudo apt-get install -y grub-pc
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
# sudo apt-get -y upgrade

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

echo 'KUBELET_EXTRA_ARGS="--cloud-provider=aws"' > /etc/default/kubelet
service kubelet stop
service kubelet start

pip3 install Flask
pip3 install awscli

export CLIENT_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
export AWS_HOSTNAME=`curl -s http://169.254.169.254/latest/meta-data/local-hostname`

echo $AWS_HOSTNAME > /etc/hostname
# echo "$CLIENT_IP k8s-master" >> /etc/hosts
hostnamectl set-hostname $AWS_HOSTNAME

sudo bash -c "cat >>/root/init.yaml" <<EOT
apiVersion: kubeadm.k8s.io/v1beta2
kind: InitConfiguration
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
localAPIEndpoint:
  advertiseAddress: $CLIENT_IP
  bindPort: 6443
nodeRegistration:
  criSocket: /var/run/dockershim.sock
  name: $AWS_HOSTNAME
  taints:
  - effect: NoSchedule
    key: node-role.kubernetes.io/master
---
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
apiServer:
  timeoutForControlPlane: 4m0s
  extraArgs:
    cloud-provider: aws
certificatesDir: /etc/kubernetes/pki
clusterName: javaperks
controllerManager:
  extraArgs:
    cloud-provider: aws
dns:
  type: CoreDNS
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: k8s.gcr.io
networking:
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12
scheduler: {}
EOT

kubeadm init --config /root/init.yaml > /root/init.txt

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

cat /root/init.txt | tail -2 > /root/kubeadm-join.txt

export KUBEJOIN="$(cat /root/kubeadm-join.txt | sed -e ':a;N;$!ba;s/ \\\n    / /g')"
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.profile
alias k=kubectl
echo "alias k=kubectl" >> /root/.profile

mkdir -p /etc/cni/net.d
mkdir -p /opt/cni/bin
sysctl net.bridge.bridge-nf-call-iptables=1
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/storage-class/aws/default.yaml"
# kubectl create -f https://raw.githubusercontent.com/kubernetes/csi-api/release-1.13/pkg/crd/manifests/csinodeinfo.yaml
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta8/aio/deploy/recommended.yaml

while [[ ! -z $(kubectl get pods --all-namespaces | sed -n '1d; /Running/ !p') ]]; do
    sleep 5
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

while [[ ! -z $(kubectl get nodes | sed -n '1d; /NotReady/ p') ]]; do
    sleep 5
done

# kubectl label node failure-domain.beta.kubernetes.io/region=us-east-1 --all
# kubectl label node failure-domain.beta.kubernetes.io/zone=us-east-1a --all

# Install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Install Consul
cd /root
git clone https://github.com/hashicorp/consul-helm.git
sudo bash -c "cat >/root/helm-consul-values.yaml" <<EOT
# helm-consul-values.yaml
global:
  datacenter: us-dc-1

ui:
  service:
    type: 'LoadBalancer'
EOT

# helm install -f helm-consul-values.yaml hashicorp ./consul-helm

