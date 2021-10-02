## Provisioning an Anthos bare metal environment on GCP

Googlers have the ability to provision self-service Linux VMs called "CloudTop instances" which run on Google's internal infrastructure.  This guide walks Googlers through the process of using CloudTop to provision an Anthos bare metal environment inside of Google's internal `google.com` GCP Organization.  

##### Connecting to your CloudTop instance

First, ensure that you have a [CloudTop instance provisioned and powered on.](https://support.google.com/techstop/answer/2662330?hl=en&ref_topic=2683844)  Afterwards, you can connect to it and complete the rest of the ABM provisioning process.

```
# Generate a session token to connect to CloudTop
gcert

# Connect to your CloudTop instance
export CLOUDTOP_ALIAS=<This is usually your Google LDAP>
ssh ${CLOUDTOP_ALIAS}.c.googlers.com

# Generate another session token from inside CloudTop
gcert
```

##### Installing CLI tooling on your new CloudTop instance.

New Linux CloudTop instances have neither `gcloud` nor `kubectl` installed on them by default.  The first time you access your CloudTop instance you will need to run the following commands to download these CLI tools.

*NOTE: This step only needs to done once.*

```
# Install gcloud and kubectl
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get install apt-transport-https ca-certificates gnupg
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
sudo apt-get update && sudo apt-get install google-cloud-sdk
sudo apt-get install google-cloud-sdk-app-engine-java
sudo apt-get install kubectl

# Authenticate with gcloud
gcloud auth login
```

Now you are ready to run the following commands from inside your new CloudTop session.

##### Download quickstart repo
```
git clone https://github.com/bbhuston/abm-quickstart-for-googlers.git
cd abm-quickstart-for-googlers
git fetch && git checkout v0.1.3
```

##### Check out available commands 
```
make help
```

##### Set your GCP Project settings
```
PROJECT_ID=<Enter your Anthos bare metal GCP Project ID>
PROJECT_NUMBER=<Enter your Anthos bare metal GCP Project Number>
USER_EMAIL=<Enter the email address associated with your GCP project (e.g., benhuston@google.com)>
DOMAIN=<Enter a routable Cloud DNS domain (e.g., cloud-for-cool-people.ninja)>

make persist-settings -e PROJECT_ID=${PROJECT_ID} -e PROJECT_NUMBER=${PROJECT_NUMBER} -e USER_EMAIL=${USER_EMAIL} -e DOMAIN=${DOMAIN}
```

##### Set default GCP Project
```
make set-gcp-project
```

##### Enable GCP APIs
```
make enable-gcp-apis
```

##### Configure IAM permissions
```
make configure-iam
```

##### Create a configuration storage bucket
```
make create-config-bucket
```

##### Create VMs
```
make create-vms
```

##### Prepare an ABM hybrid cluster
```
make create-abm-cluster -e CLUSTER_NAME=hybrid-cluster-001
```

##### Prepare an ABM user cluster
```
make create-abm-cluster -e CLUSTER_NAME=user-cluster-001
```

##### Configure Google Identity Login
```
# hybrid cluster
make google-identity-login -e CLUSTER_NAME=hybrid-cluster-001

# user cluster
make google-identity-login -e CLUSTER_NAME=user-cluster-001
```

##### Configure Cloud Build Hybrid

IMPORTANT:  Cloud Build Hybrid is still in Private Preview, so you will first need to complete [this form](https://docs.google.com/forms/d/e/1FAIpQLSeLji5duBK2TDuWErlL-tjvbnyRVgVmmE6rLU4WuqcSax4KdA/viewform) in order to be allow-listed to access the API.

To use this feature you will need to create a container registry that can be used for pushing and pulling images.
```
make create-artifact-registry 
```

Once you have been granted access to the Private Preview API, run the following command to install the Cloud Build Hybrid controller.
```
# hybrid cluster
make cloud-build-hybrid -e CLUSTER_NAME=hybrid-cluster-001

# user cluster
make cloud-build-hybrid -e CLUSTER_NAME=user-cluster-001
```

Finally, run a test build to confirm that Cloud Build Hybrid is working as expected
```
make test-cloud-build -e CLUSTER_NAME=hybrid-cluster-001
```

## Troubleshooting

If you hit any issues with your ABM installation.  The following commands will generate some useful troubleshooting information.

##### Check the status of the ABM bootstrap (aka kind cluster)
```
make check-bootstrap-status
```

##### Create a diagnostic snapshot
```
# For example, this generates a snapshot for a user cluster
make get-diagnostic-snapshot -e CLUSTER_NAME=user-cluster-001
```

## Cleaning up

Once you are finished experimenting with your ABM clusters, you can gracefully tear them down by running the following commands.

##### Remove all ABM cluster components
```
# Reset the user cluster first because it has a dependancy on the hybrid cluster
make reset-cluster -e CLUSTER_NAME=user-cluster-001

# Finally reset the hybrid cluster
make reset-cluster -e CLUSTER_NAME=hybrid-cluster-001
```

##### Delete the VMS
```
make delete-vms
```