.ONESHELL:
.EXPORT_ALL_VARIABLES:

####################################################################
# SET ANTHOS BARE METAL VARIABLES
####################################################################

ZONE=us-central1-a
MACHINE_TYPE=n1-standard-4
VM_COUNT=10
ABM_VERSION=1.7.0

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

####################################################################
# ANTHOS BARE METAL CLUSTER PREPARATION
####################################################################

prepare-hybrid-cluster:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	mkdir -p bmctl-workspace/hybrid-cluster-001
	wget -O bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/main/abm-clusters/hybrid-cluster-001.yaml
	sed -i 's/ABM_VERSION/${ABM_VERSION}/' bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001.yaml
	sed -i 's/PROJECT_ID/${PROJECT_ID}/' bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001.yaml
	EOF
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo
	@echo 'You have now connected to the ABM workstation.  Run "bmctl create cluster -c hybrid-cluster-001" to create a hybrid cluster.'
	@echo
	@echo  'After you have finished creating the ABM hybrid cluster run the following commmands to connect to it.'
	@echo
	@echo "export KUBECONFIG=$HOME/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig"
	@echo "kubectl get nodes"
	@echo
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'

prepare-user-clusters:
	# TODO: Add user cluster hydration steps

####################################################################
# INSTALL ANTHOS FEATUTES
####################################################################

install-google-identity-login:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	wget -O bmctl-workspace/hybrid-cluster-001/google-identity-login.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/feat/GH-7/anthos-features/google-identity-login.yaml
	sed -i 's/example-user@google.com/${USER_EMAIL}/' bmctl-workspace/hybrid-cluster-001/google-identity-login.yaml
	kubectl apply -f anthos-features/google-identity-login.yaml --kubeconfig=KUBECONFIG=$HOME/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	EOF

####################################################################
# ANTHOS BARE METAL WORKSTATION UTILS
####################################################################

connect-to-abm-workstation:
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30
