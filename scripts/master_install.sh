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
    gnupg2

sudo apt-get install -y \
    containerd.io=1.2.13-1 \
    docker-ce=5:19.03.8~3-0~ubuntu-$(lsb_release -cs) \
    docker-ce-cli=5:19.03.8~3-0~ubuntu-$(lsb_release -cs)

sudo apt-get install -y \
    kubelet \
    kubeadm \
    kubectl

# Setup daemon.
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

mkdir -p /etc/systemd/system/docker.service.d

# Restart docker.
systemctl enable docker
systemctl daemon-reload
systemctl restart docker

pip3 install Flask
pip3 install awscli

export CLIENT_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
export AWS_HOSTNAME=`curl -s http://169.254.169.254/latest/meta-data/local-hostname`

echo $AWS_HOSTNAME > /etc/hostname
# echo "$CLIENT_IP k8s-master" >> /etc/hosts
hostnamectl set-hostname $AWS_HOSTNAME

sudo bash -c "cat >>/root/controller.yaml" <<EOT
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-controller-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:cloud-controller-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: cloud-controller-manager
  namespace: kube-system
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    k8s-app: cloud-controller-manager
  name: cloud-controller-manager
  namespace: kube-system
spec:
  selector:
   matchLabels:
    k8s-app: cloud-controller-manager
  template:
    metadata:
      labels:
        k8s-app: cloud-controller-manager
    spec:
      serviceAccountName: cloud-controller-manager
      containers:
      - name: cloud-controller-manager
        image: jubican/aws-cloud-controller-manager:1.0.0
        command:
        - /bin/aws-cloud-controller-manager
        - --leader-elect=true
      tolerations:
      - key: node.cloudprovider.kubernetes.io/uninitialized
        value: "true"
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      nodeSelector:
        node-role.kubernetes.io/master: ""
EOT

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
  kubeletExtraArgs:
    cloud-provider: aws
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
echo 'KUBELET_EXTRA_ARGS="--cloud-provider=aws"' > /etc/default/kubelet
service kubelet restart

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
kubectl apply -f /root/controller.yaml

while [[ ! -z $(kubectl get pods --all-namespaces | sed -n '1d; /Running/ !p') ]]; do
    sleep 5
done

touch /root/patchnodes.sh
sudo bash -c "cat >/root/ready.py" <<EOT
from flask import Flask
from flask import request

app = Flask(__name__)

@app.route('/')
def hello():
    az = request.args.get("az")
    iid = request.args.get("id")
    host = request.args.get("host")
    f = open("/root/patchnodes.sh", "a")
    f.write("kubectl patch node "+host+" -p '{\"spec\":{\"providerID\":\"aws:///"+az+"/"+iid+"\"}}'\n")
    f.close()
    return "$KUBEJOIN"

if __name__ == '__main__':
    app.run(host='0.0.0.0')
EOT

python3 /root/ready.py &

while [[ ! -z $(kubectl get nodes | sed -n '1d; /NotReady/ p') ]]; do
    sleep 5
done

sleep 30
chmod +x /root/patchnodes.sh
/root/patchnodes.sh

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

syncCatalog:
  enabled: true
EOT

helm install -f helm-consul-values.yaml hashicorp ./consul-helm
