# Modified from: https://cloud.google.com/anthos/clusters/docs/bare-metal/1.6/try/gce-vms
# Huge thanks to Sam Stoelinga (stoelinga@) for authoring this script
# NOTES: All shell commands use EXTRA_SSH_ARGS, which will allow shell provisioning to properly function in a google.com GCP environment

# Configure your GCP project
export PROJECT_ID=$1
export ZONE=$2

# Set VM instance type and quantity
MACHINE_TYPE=$3
VM_COUNT=$4
ABM_VERSION=$5

# Create list of VM name
declare -a VMs=()
VM_PREFIX=abm
VM_WS=abm-ws
VMs+=("$VM_WS")
for ((i=1; i<=${VM_COUNT}; i++)); do
   VMs[i]="abm-vm-$i"
done

# Create VMs and record their private IPs
declare -a IPs=()
for vm in ${VMs[@]}
do
    gcloud compute instances create $vm \
              --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud \
              --zone=${ZONE} \
              --boot-disk-size 200G \
              --boot-disk-type pd-ssd \
              --can-ip-forward \
              --network default \
              --tags http-server,https-server,abm-demo \
              --min-cpu-platform "Intel Haswell" \
              --scopes cloud-platform \
              --machine-type $MACHINE_TYPE
    IP=$(gcloud compute instances describe $vm --zone ${ZONE} \
         --format='get(networkInterfaces[0].networkIP)')
    IPs+=("$IP")
done

# Check if corp-ssh-helper is available so VPN isn't required e.g. on mac, glinux or cloudtop
EXTRA_SSH_ARGS=()
if command -v corp-ssh-helper &> /dev/null
then
  EXTRA_SSH_ARGS=(-- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30)
fi
for vm in "${VMs[@]}"
do
    while ! gcloud compute ssh root@$vm --zone ${ZONE} --command "echo SSH to $vm succeeded" "${EXTRA_SSH_ARGS[@]}"
    do
        echo "Trying to SSH into $vm failed. Sleeping for 5 seconds. zzzZZzzZZ"
        sleep  5
    done
done

i=2 # Define a VXLAN starting from 10.200.0.2/24
for vm in "${VMs[@]}"
do
    gcloud compute ssh root@$vm --zone ${ZONE} "${EXTRA_SSH_ARGS[@]}" << EOF
        apt-get -qq update > /dev/null
        apt-get -qq install -y jq > /dev/null
        set -x
        ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
        current_ip=\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
        echo "VM IP address is: \$current_ip"
        for ip in ${IPs[@]}; do
            if [ "\$ip" != "\$current_ip" ]; then
                bridge fdb append to 00:00:00:00:00:00 dst \$ip dev vxlan0
            fi
        done
        ip addr add 10.200.0.$i/24 dev vxlan0
        ip link set up dev vxlan0
        systemctl stop apparmor.service #Anthos clusters on bare metal does not support apparmor
        systemctl disable apparmor.service
EOF
    i=$((i+1))
done

# Provision ABM prerequisites on the ABM workstation
gcloud compute ssh root@$VM_WS --zone ${ZONE} "${EXTRA_SSH_ARGS[@]}" << EOF
set -x

export PROJECT_ID=\$(gcloud config get-value project)
gcloud iam service-accounts keys create bm-gcr.json \
--iam-account=baremetal-gcr@\${PROJECT_ID}.iam.gserviceaccount.com

curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"

chmod +x kubectl
mv kubectl /usr/local/sbin/
mkdir baremetal && cd baremetal
gsutil cp gs://anthos-baremetal-release/bmctl/${ABM_VERSION}/linux-amd64/bmctl .
chmod a+x bmctl
mv bmctl /usr/local/sbin/

cd ~
echo "Installing docker"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

cd ~
echo "Installing Krew"
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.tar.gz" &&
  tar zxvf krew.tar.gz &&
  KREW=./krew-"${OS}_${ARCH}" &&
  "$KREW" install krew
)
mv .krew/store/krew/v0.4.1/krew /usr/local/sbin/
krew version

echo "Installing Virt plugin"
krew install virt
kubectl virt

echo "Installing stand-alone virtctl"
VERSION=v0.45.0
wget https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-linux-amd64
chmod +x mv virtctl-${VERSION}-linux-amd64
mv virtctl-${VERSION}-linux-amd64 /usr/local/sbin/virtctl
virtctl help

echo "Installing vnc package for virtctl"
apt-get install -y virt-viewer

echo "Installing netstat"
apt install net-tools
netstat -v

EOF

# Register the ABM workstation's SSH public key with each VM
gcloud compute ssh root@$VM_WS --zone ${ZONE} "${EXTRA_SSH_ARGS[@]}" << EOF
set -x
ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa <<< y
sed 's/ssh-rsa/root:ssh-rsa/' ~/.ssh/id_rsa.pub > ssh-metadata
for vm in ${VMs[@]}
do
    gcloud compute instances add-metadata \$vm --zone ${ZONE} --metadata-from-file ssh-keys=ssh-metadata
done
EOF