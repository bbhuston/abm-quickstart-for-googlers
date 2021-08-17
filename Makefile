.ONESHELL:
.EXPORT_ALL_VARIABLES:

####################################################################
# SET ANTHOS BARE METAL VARIABLES
####################################################################

ZONE=us-central1-a
MACHINE_TYPE=n1-standard-4
VM_COUNT=10
ABM_VERSION=1.8.2
BRANCH=feat/GH-17
# Cluster name of build target for Cloud Build Hybrid
BUILD_CLUSTER=hybrid-cluster-001

# Source important variables that need to persist and are easy to forget about
include utils/env

##@ Overview

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

help: ##          Display help prompt
	@awk 'BEGIN {FS = ":.*##"; printf "\n########################################################################\n#               AMAZING! YOU ARE SUPER ANTHOS HACKERMAN!               #\n########################################################################\n\nUsage:\n\n  make \033[36m<command>\033[0m            For example, `make help` \n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

persist-settings: ##         Write environmental variables locally
	@echo "PROJECT_ID=${PROJECT_ID}" > utils/env
	@echo "PROJECT_NUMBER=${PROJECT_NUMBER}" >> utils/env
	@echo "USER_EMAIL=${USER_EMAIL}" >> utils/env
	@echo "BUILD_CLUSTER=${BUILD_CLUSTER}" >> utils/env

##@ Configuring your GCP Project

set-gcp-project:  ##          Set your default GCP project
	@gcloud config set project ${PROJECT_ID}

enable-gcp-apis:  ##          Enable GCP APIs
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

configure-iam:  ##          Bind IAM permissions to a service account
	@gcloud iam service-accounts create baremetal-gcr
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/gkehub.connect"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/gkehub.admin"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/logging.logWriter"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/monitoring.metricWriter"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/monitoring.dashboardEditor"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/stackdriver.resourceMetadata.writer"

##@ Preparing ABM Clusters

# TODO: Add tags to instances when they are created
create-vms:  ##          Create and bootstrap GCE instances
	# Top level environmental variables are passed into the the shell script positionally
	@/bin/bash utils/abm-vm-bootstrap.sh ${PROJECT_ID} ${ZONE} ${MACHINE_TYPE} ${VM_COUNT} ${ABM_VERSION}

prepare-hybrid-cluster:  ##   Copy a hybrid cluster manifest to the workstation
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
	@echo 'You have now connected to the ABM workstation.  Run "bmctl create cluster -c hybrid-cluster-001" to create a hybrid cluster.'
	@echo
	@echo  'After you have finished creating the ABM hybrid cluster run the following commmands to connect to it.'
	@echo
	@echo "export KUBECONFIG=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig"
	@echo "kubectl get nodes"
	@echo
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30

##@ Installing Anthos Features

google-identity-login:  ##    Enable Google Identity Login
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	wget -O google-identity-login.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/${BRANCH}/anthos-features/google-identity-login.yaml
	sed -i 's/example-user@google.com/${USER_EMAIL}/' google-identity-login.yaml
	kubectl apply -f google-identity-login.yaml --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	EOF

cloud-build-hybrid:  ##       Enable Cloud Build Hybrid
	@gcloud services enable cloudbuild.googleapis.com
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" --role="roles/gkehub.admin"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" --role="roles/gkehub.connect"
	@gcloud alpha container hub build enable
	@gcloud alpha container hub build install --membership=projects/${PROJECT_NUMBER}/locations/global/memberships/hybrid-cluster-001
	@gcloud iam service-accounts create cloud-build-hybrid-workload --description="cloud-build-hybrid-workload impersonation SA" --display-name="cloud-build-hybrid-workload"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/editor"
	@gcloud iam service-accounts add-iam-policy-binding --role roles/iam.workloadIdentityUser --member "serviceAccount:${PROJECT_ID}.svc.id.goog[cloudbuild/default]" cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/cloudkms.cryptoKeyDecrypter"
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	@kubectl -n cloudbuild annotate serviceaccount default iam.gke.io/gcp-service-account=cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	@wget -O cloud-build-hybrid.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/${BRANCH}/anthos-features/cloud-build-hybrid.yaml
	@kubectl apply -f cloud-build-hybrid.yaml --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	EOF

##@ Removing ABM Clusters

uninstall-hybrid-cluster:  ## Safely uninstall the hybrid cluster components
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	bmctl reset --cluster hybrid-cluster-001
	EOF

# TODO: Only delete instances that have the 'abm-demo' tag on them
delete-vms:  ##          Delete all GCE instances in the current zone
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

delete-keys: ##          [TODO] Delete GCP service account keys
	# TODO: add gcloud commands to remove stale keys

##@ Workstation Utils

connect-to-workstation:  ##   Connect the ABM workstation from Cloudtop
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30

test-abm-connection:  ##      Confirm the hybrid cluster is active
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	kubectl cluster-info --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	kubectl get nodes --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	EOF

test-cloud-build:  ##         Run a Cloud Build Hybrid job
	@sed -i 's/PROJECT_NUMBER/${PROJECT_NUMBER}/' anthos-features/cloudbuild/cloudbuild-example-001.yaml
	@sed -i 's/CLUSTER_NAME/${BUILD_CLUSTER}/' anthos-features/cloudbuild/cloudbuild-example-001.yaml
	@gcloud alpha builds submit --config=anthos-features/cloudbuild/cloudbuild-example-001.yaml --no-source