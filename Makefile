.ONESHELL:
.SILENT:
.EXPORT_ALL_VARIABLES:

####################################################################
# SET ANTHOS BARE METAL VARIABLES
####################################################################

ZONE=us-central1-a
REGION=us-central1
MACHINE_TYPE=n1-standard-4
VM_COUNT=10
ABM_VERSION=1.8.4
ASM_VERSION=asm-178-8
# Name of default cluster to enable Anthos features on
CLUSTER_NAME=hybrid-cluster-001

# Source important variables that need to be persisted and are easy to forget about
-include utils/env

# Define special SSH settings required for Google-managed devices
CORP_SETTINGS=-- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30

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

##@ Configuring your GCP Project

persist-settings: ##         Write environmental variables locally
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Writing your settings to utils/env...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@echo "PROJECT_ID=${PROJECT_ID}" > utils/env
	@echo "PROJECT_NUMBER=${PROJECT_NUMBER}" >> utils/env
	@echo "USER_EMAIL=${USER_EMAIL}" >> utils/env
	@echo "DOMAIN=${DOMAIN}" >> utils/env
	@echo "CLUSTER_NAME=${CLUSTER_NAME}" >> utils/env

set-gcp-project:  ##          Set your default GCP project
	@gcloud config set project ${PROJECT_ID}

enable-gcp-apis:  ##          Enable GCP APIs
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Activating Google Cloud APIs...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	# Anthos APIs
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
        opsconfigmonitoring.googleapis.com \
        anthosaudit.googleapis.com
	# Cloud DNS APIs
	@gcloud services enable \
		dns.googleapis.com \
		domains.googleapis.com
	# Apigee Hybrid APIs
	@gcloud services enable \
        logging.googleapis.com \
		apigee.googleapis.com \
		apigeeconnect.googleapis.com \
		pubsub.googleapis.com \
		compute.googleapis.com
	# Cloud Build APIs
	@gcloud services enable \
		cloudbuild.googleapis.com
	# Artifact Registry APIs
	@gcloud services enable \
		artifactregistry.googleapis.com

configure-iam:  ##          Bind IAM permissions to a service account
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Configuring IAM permissions...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	# Anthos IAM
	@gcloud iam service-accounts create baremetal-gcr
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/gkehub.connect"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/gkehub.admin"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/logging.logWriter"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/monitoring.metricWriter"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/monitoring.dashboardEditor"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/stackdriver.resourceMetadata.writer"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/opsconfigmonitoring.resourceMetadata.writer"
	# Cloud Build Hybrid IAM
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" --role="roles/gkehub.admin"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" --role="roles/gkehub.connect"

create-dns-zone:  ##          Create a Cloud DNS domain
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Creating a new Cloud DNS zone...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@gcloud dns managed-zones create apigee-hybrid-dns-zone \
    	--description="Apigee Hybrid DNS Zone" \
        --dns-name=${DOMAIN} \
        --visibility=public

create-artifact-registry:  ## Create Artifact Registry
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Creating a new Artifact Registry...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@gcloud artifacts repositories create cloud-build-hybrid-container-registry \
		--repository-format=DOCKER --location=us --description="Example Artifact Registry"
	@gcloud artifacts repositories describe cloud-build-hybrid-container-registry --location=us

create-config-bucket:  ##     Create Cloud Storage config file bucket
	@gsutil mb -b on -l us-central1 gs://${PROJECT_ID}-config-bucket/

##@ Preparing ABM Clusters

create-vms:  ##          Create and bootstrap GCE instances
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Provisioning new VMs now...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	# Top level environmental variables are passed into the the shell script positionally
	@/bin/bash utils/abm-vm-bootstrap.sh ${PROJECT_ID} ${ZONE} ${MACHINE_TYPE} ${VM_COUNT} ${ABM_VERSION}

create-abm-cluster:  ##       Create an ABM cluster
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Creating ABM cluster ${CLUSTER_NAME} now...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@gsutil cp abm-clusters/${CLUSTER_NAME}.yaml gs://benhuston-abm-config-bucket/${CLUSTER_NAME}.yaml
	@gcloud compute ssh root@abm-ws --zone ${ZONE} ${CORP_SETTINGS} << EOF
	mkdir -p bmctl-workspace/${CLUSTER_NAME}
	gsutil cp gs://benhuston-abm-config-bucket/${CLUSTER_NAME}.yaml bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}.yaml
	sed -i 's/ABM_VERSION/${ABM_VERSION}/' bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}.yaml
	sed -i 's/PROJECT_ID/${PROJECT_ID}/' bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}.yaml
	if [ ${CLUSTER_NAME} = 'hybrid-cluster-001' ]; then \
 		bmctl create cluster -c ${CLUSTER_NAME} --reuse-bootstrap-cluster; \
	else \
		bmctl create cluster -c ${CLUSTER_NAME} --reuse-bootstrap-cluster --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig; \
	fi
	EOF

##@ Enabling Anthos Features

google-identity-login:  ##    Enable Google Identity Login
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Enabling Google Identity Login...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@gsutil cp anthos-features/google-identity-login/google-identity-login-rbac.yaml gs://benhuston-abm-config-bucket/google-identity-login-rbac.yaml
	@gcloud compute ssh root@abm-ws --zone ${ZONE} ${CORP_SETTINGS} << EOF
	@gsutil cp gs://benhuston-abm-config-bucket/google-identity-login-rbac.yaml google-identity-login-rbac.yaml
	sed -i 's/example-user@google.com/${USER_EMAIL}/' google-identity-login-rbac.yaml
	sed -i 's/PROJECT_NUMBER/${PROJECT_NUMBER}/' google-identity-login-rbac.yaml
	kubectl apply -f google-identity-login-rbac.yaml --kubeconfig=/root/bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig
	EOF

cloud-build-hybrid:  ##       Enable Cloud Build Hybrid
	@gcloud alpha container hub build enable
	@gcloud alpha container hub build install --membership=projects/${PROJECT_NUMBER}/locations/global/memberships/${CLUSTER_NAME}
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Enabling Cloud Build Hybrid...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 160s
	@gcloud alpha container hub build describe
	@gcloud iam service-accounts create cloud-build-hybrid-workload --description="cloud-build-hybrid-workload impersonation SA" --display-name="cloud-build-hybrid-workload"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/editor"
	@gcloud iam service-accounts add-iam-policy-binding --role roles/iam.workloadIdentityUser --member "serviceAccount:${PROJECT_ID}.svc.id.goog[cloudbuild/default]" cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com
	@gcloud iam service-accounts add-iam-policy-binding --role roles/iam.workloadIdentityUser --member "serviceAccount:${PROJECT_ID}.svc.id.goog[cloudbuild-examples/cloud-build-hybrid]" cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/cloudkms.cryptoKeyDecrypter"
	@gsutil cp anthos-features/cloud-build-hybrid/cloud-build-hybrid-rbac.yaml gs://benhuston-abm-config-bucket/cloud-build-hybrid-rbac.yaml
	@gcloud compute ssh root@abm-ws --zone ${ZONE} ${CORP_SETTINGS} << EOF
	@gsutil cp gs://benhuston-abm-config-bucket/cloud-build-hybrid-rbac.yaml cloud-build-hybrid-rbac.yaml
	@kubectl -n cloudbuild annotate serviceaccount default iam.gke.io/gcp-service-account=cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com --overwrite=true --kubeconfig=/root/bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig
	@kubectl apply -f cloud-build-hybrid-rbac.yaml --kubeconfig=/root/bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Creating an image pull secret...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@gcloud iam service-accounts keys create artifact-registry.json --iam-account=baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com
	@kubectl -n cloudbuild-examples create secret docker-registry artifact-registry --docker-server=https://us-docker.pkg.dev --docker-email=cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com --docker-username=_json_key --docker-password='\$$(cat artifact-registry.json)' --kubeconfig=/root/bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig
	EOF

reset-cluster:  ##          Safely remove all cluster components
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Removing all ABM cluster components...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@gcloud compute ssh root@abm-ws --zone ${ZONE} ${CORP_SETTINGS} << EOF
	bmctl reset --cluster ${CLUSTER_NAME}
	EOF

# TODO: Only delete instances that have the 'abm-demo' tag on them
delete-vms: delete-keys ##          Delete all GCE instances in the current zone
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Deleting VMs...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
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

delete-keys: ##          Delete GCP service account keys used by ABM
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Deleting ABM service account keys...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	gcloud iam service-accounts keys list --managed-by=user --iam-account=baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com | awk '{ print $$1 }' |  tail -n +2 > temp.txt
	while read line; do gcloud iam service-accounts keys delete $$line --iam-account=baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com --quiet; done < temp.txt
	rm temp.txt

##@ Workstation Utils

connect-to-workstation:  ##   Connect the ABM workstation from Cloudtop
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Connecting to your ABM workstation...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@gcloud compute ssh root@abm-ws --zone ${ZONE} ${CORP_SETTINGS}

test-abm-connection:  ##      Confirm the hybrid cluster is active
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Verifying that your ABM cluster is reachable...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@gcloud compute ssh root@abm-ws --zone ${ZONE} ${CORP_SETTINGS} << EOF
	kubectl cluster-info --kubeconfig=/root/bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig
	kubectl get nodes --kubeconfig=/root/bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig
	EOF

test-cloud-build:  ##         Run a Cloud Build Hybrid job
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Running a quick Cloud Build Hybrid test...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@sed -i 's/PROJECT_ID/${PROJECT_ID}/' anthos-features/cloud-build-hybrid/deployment.yaml
	@gcloud alpha builds submit --config=anthos-features/cloud-build-hybrid/cloud-build-hybrid-example-001.yaml --no-source --substitutions=_CLUSTER_NAME=${CLUSTER_NAME}

check-bootstrap-status:  ##   Check the status of ABM installation bootstrap
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Checking the status of the ABM cluster bootstrap...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@gcloud compute ssh root@abm-ws --zone ${ZONE} ${CORP_SETTINGS} << EOF
	@kubectl get pod -A --kubeconfig=bmctl-workspace/.kindkubeconfig
	EOF

get-diagnostic-snapshot:  ##  Create a diagnostic snapshot for troubleshooting
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Creating a cluster snapshot... logs are being written to the "bmctl-workspace/${CLUSTER_NAME}/log/check-cluster" directory
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 3s
	@gcloud compute ssh root@abm-ws --zone ${ZONE} ${CORP_SETTINGS} << EOF
	@bmctl check cluster --snapshot-scenario all --cluster ${CLUSTER_NAME} --snapshot-config=/root/bmctl-workspace/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig
	EOF