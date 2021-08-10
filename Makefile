.ONESHELL:
.EXPORT_ALL_VARIABLES:

####################################################################
# SET ANTHOS BARE METAL VARIABLES
####################################################################

ZONE=us-central1-a
MACHINE_TYPE=n1-standard-4
VM_COUNT=10
ABM_VERSION=1.8.2
BRANCH=feat/GH-10

# Source important variables that need to persist and are easy to forget about
include utils/env

persist-settings:
	@echo "PROJECT_ID=${PROJECT_ID}" > utils/env
	@echo "USER_EMAIL=${USER_EMAIL}" >> utils/env

####################################################################
# CONFIGURE GCP PROJECT
####################################################################

set-default-gcp-project:
	@gcloud config set project ${PROJECT_ID}

enable-gcp-apis:
	@gcloud services enable \
        anthos.googleapis.com \
        anthosgke.googleapis.com \
        cloudresourcemanager.googleapis.com \
        container.googleapis.com \
        gkeconnect.googleapis.com \
        gkehub.googleapis.com \
        serviceusage.googleapis.com \
        stackdriver.googleapis.com \
        monitoring.googleapis.com \
        logging.googleapis.com

configure-iam-permissions:
	@gcloud iam service-accounts create baremetal-gcr
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/gkehub.connect"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/gkehub.admin"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/logging.logWriter"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/monitoring.metricWriter"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/monitoring.dashboardEditor"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/stackdriver.resourceMetadata.writer"

####################################################################
# VM LIFECYCLE MANAGEMENT
####################################################################

create-vms:
	# Top level environmental variables are passed into the the shell script positionally
	@/bin/bash utils/abm-vm-bootstrap.sh ${PROJECT_ID} ${ZONE} ${MACHINE_TYPE} ${VM_COUNT} ${ABM_VERSION}

delete-vms:
	@export VM_WS=abm-ws
	# Create list of VM names
	@export VMs=()
	VMs+=("$$VM_WS")
	for ((i=1; i<=$${VM_COUNT}; i++)); do
	   VMs[i]="abm-vm-$$i"
	done
	# Delete VMs
	for vm in "$${VMs[@]}"
	do
	    gcloud compute instances delete $$vm --zone=${ZONE} --quiet
	done

delete-abm-service-acount-keys:
	# TODO: add gcloud commands to remove stale keys

####################################################################
# ANTHOS BARE METAL CLUSTER PREPARATION
####################################################################

prepare-hybrid-cluster:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	mkdir -p bmctl-workspace/hybrid-cluster-001
	wget -O bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/${BRANCH}/abm-clusters/hybrid-cluster-001.yaml
	sed -i 's/ABM_VERSION/${ABM_VERSION}/' bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001.yaml
	sed -i 's/PROJECT_ID/${PROJECT_ID}/' bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001.yaml
	EOF
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo
	@echo 'You have now connected to the ABM workstation.  Run "bmctl create cluster -c hybrid-cluster-001 --force" to create a hybrid cluster.'
	@echo
	@echo  'After you have finished creating the ABM hybrid cluster run the following commmands to connect to it.'
	@echo
	@echo "export KUBECONFIG=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig"
	@echo "kubectl get nodes"
	@echo
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30

prepare-user-cluster-with-metallb:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	mkdir -p bmctl-workspace/user-cluster-001
	wget -O bmctl-workspace/user-cluster-001/user-cluster-001.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/${BRANCH}/abm-clusters/user-cluster-001.yaml
	sed -i 's/ABM_VERSION/${ABM_VERSION}/' bmctl-workspace/user-cluster-001/user-cluster-001.yaml
	sed -i 's/PROJECT_ID/${PROJECT_ID}/' bmctl-workspace/user-cluster-001/user-cluster-001.yaml
	EOF
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo
	@echo 'You have now connected to the ABM workstation.  To create a user cluster run:'
	@echo
	@echo "kubectl apply -f bmctl-workspace/user-cluster-001/user-cluster-001.yaml --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig"
	@echo
	@echo
	@echo 'To check the status of the user cluster run:'
	@echo
	@echo 'kubectl describe cluster user-cluster-001 -n abm-user-cluster-001  --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig'
	@echo
	@echo
	@echo 'After you have finished creating the ABM user cluster run the following commmands to connect to it.'
	@echo
	@echo "kubectl -n abm-user-cluster-001 get secret user-cluster-001-kubeconfig -o 'jsonpath={.data.value}' --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig | base64 -d > /root/bmctl-workspace/user-cluster-001/user-cluster-001-kubeconfig"
	@echo "export KUBECONFIG=/root/bmctl-workspace/user-cluster-001/user-cluster-001-kubeconfig"
	@echo "kubectl get nodes"
	@echo
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30

prepare-user-cluster-with-gce-lb:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	mkdir -p bmctl-workspace/user-cluster-002
	wget -O bmctl-workspace/user-cluster-002/user-cluster-002.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/${BRANCH}/abm-clusters/user-cluster-002.yaml
	sed -i 's/ABM_VERSION/${ABM_VERSION}/' bmctl-workspace/user-cluster-002/user-cluster-002.yaml
	sed -i 's/PROJECT_ID/${PROJECT_ID}/' bmctl-workspace/user-cluster-002/user-cluster-002.yaml
	EOF
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo
	@echo 'You have now connected to the ABM workstation.  To create a user cluster run:'
	@echo
	@echo "kubectl apply -f bmctl-workspace/user-cluster-002/user-cluster-002.yaml --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig"
	@echo
	@echo
	@echo 'To check the status of the user cluster run:'
	@echo
	@echo 'kubectl describe cluster user-cluster-002 -n abm-user-cluster-002  --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig'
	@echo
	@echo
	@echo 'After you have finished creating the ABM user cluster run the following commmands to connect to it.'
	@echo
	@echo "kubectl -n abm-user-cluster-002 get secret user-cluster-002-kubeconfig -o 'jsonpath={.data.value}' --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig | base64 -d > /root/bmctl-workspace/user-cluster-002/user-cluster-002-kubeconfig"
	@echo "export KUBECONFIG=/root/bmctl-workspace/user-cluster-002/user-cluster-002-kubeconfig"
	@echo "kubectl get nodes"
	@echo
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30

####################################################################
# INSTALL ANTHOS FEATURES
####################################################################

install-google-identity-login:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	wget -O google-identity-login.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/${BRANCH}/anthos-features/google-identity-login.yaml
	sed -i 's/example-user@google.com/${USER_EMAIL}/' google-identity-login.yaml
	kubectl apply -f google-identity-login.yaml --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	kubectl apply -f google-identity-login.yaml --kubeconfig=/root/bmctl-workspace/user-cluster-001/user-cluster-001-kubeconfig
	kubectl apply -f google-identity-login.yaml --kubeconfig=/root/bmctl-workspace/user-cluster-002/user-cluster-002-kubeconfig
	EOF

####################################################################
# ANTHOS BARE METAL WORKSTATION UTILS
####################################################################

connect-to-abm-workstation:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30

uninstall-hybrid-cluster:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	bmctl reset --cluster hybrid-cluster-001
	EOF

test-hybrid-cluster-connection:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	kubectl cluster-info --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	kubectl get nodes --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	EOF