.ONESHELL:
.EXPORT_ALL_VARIABLES:

####################################################################
# SET ANTHOS BARE METAL VARIABLES
####################################################################

ZONE=us-central1-a
REGION=us-central1
MACHINE_TYPE=n1-standard-4
VM_COUNT=10
ABM_VERSION=1.8.3
ASM_VERSION=asm-178-8
BRANCH=feat/GH-19
# Cluster name of the default build target for Cloud Build Hybrid
BUILD_CLUSTER=hybrid-cluster-001

# Source important variables that need to be persisted and are easy to forget about
-include utils/env

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
	@echo "PROJECT_ID=${PROJECT_ID}" > utils/env
	@echo "PROJECT_NUMBER=${PROJECT_NUMBER}" >> utils/env
	@echo "USER_EMAIL=${USER_EMAIL}" >> utils/env
	@echo "DOMAIN=${DOMAIN}" >> utils/env
	@echo "BUILD_CLUSTER=${BUILD_CLUSTER}" >> utils/env

set-gcp-project:  ##          Set your default GCP project
	@gcloud config set project ${PROJECT_ID}

enable-gcp-apis:  ##          Enable GCP APIs
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
        monitoring.googleapis.com
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
	# Anthos IAM
	@gcloud iam service-accounts create baremetal-gcr
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/gkehub.connect"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/gkehub.admin"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/logging.logWriter"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/monitoring.metricWriter"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/monitoring.dashboardEditor"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/stackdriver.resourceMetadata.writer"
	# Cloud Build Hybrid IAM
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" --role="roles/gkehub.admin"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" --role="roles/gkehub.connect"

create-dns-zone:  ##          Create a Cloud DNS domain
	@gcloud dns managed-zones create apigee-hybrid-dns-zone \
    	--description="Apigee Hybrid DNS Zone" \
        --dns-name=${DOMAIN} \
        --visibility=public

create-artifact-registry:  ## Create Artifact Registry
	@gcloud artifacts repositories create cloud-build-hybrid-container-registry \
		--repository-format=DOCKER --location=us --description="Example Artifact Registry"
	@gcloud artifacts repositories describe cloud-build-hybrid-container-registry --location=us

create-config-bucket:  ##     Create Cloud Storage config file bucket
	@gsutil mb -b on -l us-central1 gs://${PROJECT_ID}-abm-config-bucket/

##@ Preparing ABM Clusters

create-vms:  ##          Create and bootstrap GCE instances
	# Top level environmental variables are passed into the the shell script positionally
	@/bin/bash utils/abm-vm-bootstrap.sh ${PROJECT_ID} ${ZONE} ${MACHINE_TYPE} ${VM_COUNT} ${ABM_VERSION}

prepare-hybrid-cluster:  ##   Copy a hybrid cluster manifest to the workstation
	@scp abm-clusters/hybrid-cluster-001.yaml root@35.226.213.176:/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001.yaml
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	mkdir -p bmctl-workspace/hybrid-cluster-001
	#wget -O bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/${BRANCH}/abm-clusters/hybrid-cluster-001.yaml
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
	wget -O google-identity-login-rbac.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/${BRANCH}/anthos-features/google-identity-login/google-identity-login-rbac.yaml
	sed -i 's/example-user@google.com/${USER_EMAIL}/' google-identity-login-rbac.yaml
	sed -i 's/PROJECT_NUMBER/${PROJECT_NUMBER}/' google-identity-login-rbac.yaml
	kubectl apply -f google-identity-login-rbac.yaml --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	EOF

#anthos-service-mesh:   ##      Enable Anthos Service Mesh
#	# NOTE:  Version 1.7.x of Anthos Service Mesh (ASM) is currently the only version supported by Apigee Hybrid
#	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
#	@kubectl create namespace istio-system --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
#	@istioctl install --set profile=asm-multicloud --set revision=${ASM_VERSION}
#	@kubectl apply -f istiod-service.yaml --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
#	@kubectl label namespace istio-system istio-injection-istio.io/rev=${ASM_VERSION} --overwrite
#	EOF

cloud-build-hybrid:  ##       Enable Cloud Build Hybrid
	@gcloud alpha container hub build enable
	@gcloud alpha container hub build install --membership=projects/${PROJECT_NUMBER}/locations/global/memberships/hybrid-cluster-001
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Waiting for Cloud Build Hybrid installation to finish...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@sleep 180s
	@gcloud alpha container hub build describe
	@gcloud iam service-accounts create cloud-build-hybrid-workload --description="cloud-build-hybrid-workload impersonation SA" --display-name="cloud-build-hybrid-workload"
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/editor"
	@gcloud iam service-accounts add-iam-policy-binding --role roles/iam.workloadIdentityUser --member "serviceAccount:${PROJECT_ID}.svc.id.goog[cloudbuild/default]" cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com
	@gcloud iam service-accounts add-iam-policy-binding --role roles/iam.workloadIdentityUser --member "serviceAccount:${PROJECT_ID}.svc.id.goog[cloudbuild-examples/cloud-build-hybrid]" cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com
	@gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/cloudkms.cryptoKeyDecrypter"
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	@kubectl -n cloudbuild annotate serviceaccount default iam.gke.io/gcp-service-account=cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com --overwrite=true --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	@wget -O cloud-build-hybrid-rbac.yaml https://raw.githubusercontent.com/bbhuston/abm-quickstart-for-googlers/${BRANCH}/anthos-features/cloud-build-hybrid/cloud-build-hybrid-rbac.yaml
	@kubectl apply -f cloud-build-hybrid-rbac.yaml --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	@echo '-----------------------------------------------------------------------------------------------------'
	@echo
	@echo 	Creating image pull secret...
	@echo
	@echo '-----------------------------------------------------------------------------------------------------'
	@gcloud iam service-accounts keys create artifact-registry.json --iam-account=baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com
	@kubectl -n cloudbuild-examples create secret docker-registry artifact-registry --docker-server=https://us-docker.pkg.dev --docker-email=cloud-build-hybrid-workload@${PROJECT_ID}.iam.gserviceaccount.com --docker-username=_json_key --docker-password='\$$(cat artifact-registry.json)' --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	EOF

apigee-hybrid: apigee-environments apigee-runtime   ##          Enable Apigee Hybrid
	# Create environments and install runtime

apigee-environments:
	# Create an Apigee Organization
	@curl -H "Authorization: Bearer $$(gcloud auth print-access-token)" -X POST -H "content-type:application/json" "https://apigee.googleapis.com/v1/organizations?parent=projects/${PROJECT_ID}" \
    	-d '{ "name": "${PROJECT_ID}", "displayName": "${PROJECT_ID}", "description": "Apigee Hybrid Organization", "runtimeType": "HYBRID", "analyticsRegion": "${REGION}" }'
	# Create dev, staging, and prod Apigee environments
	@curl -H "Authorization: Bearer $$(gcloud auth print-access-token)" -X POST -H "content-type:application/json" \
		-d '{"name": "development", "displayName": "development", "description": "development"}'   "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/environments"
	@curl -H "Authorization: Bearer $$(gcloud auth print-access-token)" -X POST -H "content-type:application/json" \
		-d '{"name": "staging", "displayName": "staging", "description": "staging"}'   "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/environments"
	@curl -H "Authorization: Bearer $$(gcloud auth print-access-token)" -X POST -H "content-type:application/json" \
		-d '{"name": "production", "displayName": "production", "description": "production"}'   "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/environments"
	# Create an environment group called 'api-environments'
	@curl -H "Authorization: Bearer $$(gcloud auth print-access-token)" -X POST -H "content-type:application/json" "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/envgroups" \
		-d '{ "name": "api-environments", "hostnames":["${DOMAIN}"] }'
	# Register environments with the environment group
	@curl -H "Authorization: Bearer $$(gcloud auth print-access-token)" -X POST -H "content-type:application/json" "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/envgroups/api-environments/attachments" \
		-d '{"environment": "development",}'
	@curl -H "Authorization: Bearer $$(gcloud auth print-access-token)" -X POST -H "content-type:application/json" "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/envgroups/api-environments/attachments" \
		-d '{"environment": "staging",}'
	@curl -H "Authorization: Bearer $$(gcloud auth print-access-token)" -X POST -H "content-type:application/json" "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/envgroups/api-environments/attachments" \
		-d '{"environment": "production",}'

apigee-runtime:
	# Install the Apigee Hybrid runtime
	# TODO: Resolve version conflict between cert-manager for Apigee Hybrid and ABM
	# @kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.2.0/cert-manager.yaml

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

#delete-keys: ##          Delete GCP service account keys
#	# TODO: Add gcloud commands to remove stale keys

##@ Workstation Utils

connect-to-workstation:  ##   Connect the ABM workstation from Cloudtop
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30

test-abm-connection:  ##      Confirm the hybrid cluster is active
	@gcloud compute ssh root@abm-ws --zone ${ZONE} -- -o ProxyCommand='corp-ssh-helper %h %p' -ServerAliveInterval=30 -o ConnectTimeout=30 << EOF
	kubectl cluster-info --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	kubectl get nodes --kubeconfig=/root/bmctl-workspace/hybrid-cluster-001/hybrid-cluster-001-kubeconfig
	EOF

test-cloud-build:  ##         Run a Cloud Build Hybrid job
	@sed -i 's/PROJECT_ID/${PROJECT_ID}/' anthos-features/cloud-build-hybrid/deployment.yaml
	@gcloud alpha builds submit --config=anthos-features/cloud-build-hybrid/cloud-build-hybrid-example-001.yaml --no-source --substitutions=_CLUSTER_NAME=${BUILD_CLUSTER}