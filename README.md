# Provisioning an Anthos bare metal environment on GCP

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

Now you are ready to run the following commmands from inside your new CloudTop session.

##### Download quickstart repo
```
git clone https://github.com/bbhuston/abm-quickstart-for-googlers.git
cd abm-quickstart-for-googlers
git fetch && git checkout v0.1.1
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

##### Create VMs
```
make create-vms
```

##### Prepare an ABM hybrid cluster
```
make prepare-hybrid-cluster
```

##### Configure Google Identity Login
```
make google-identity-login
```

##### Configure Anthos Service Mesh

NOTE: This step installs Anthos Service Mesh (ASM) version 1.7.x  because this is the most recent version of ASM that is supported by Apigee Hybrid.
```
make anthos-service-mesh
```

##### Configure Cloud Build Hybrid
```
make cloud-build-hybrid
```

Run a test build to confirm that Cloud Build Hybrid is working as expected
```
make test-cloud-build
```

##### Configure Apigee Hybrid

Enable the Apigee Hybrid APIs
```
make apigee-apis
```

Create a Cloud DNS zone and associate it with a Cloud Domain if you do not already have one.
```
make create-dns-zone
```

Run the following command to register your domain (e.g., cloud-for-cool-people.ninja), if you do not already have one.  This command will guide through a sequence of interactive prompts which you can use to provide your domain registrant information.
```
gcloud beta domains registrations register ${DOMAIN}
```

Create Apigee Hybrid 'environments' and 'groups'
```
make apigee-environs
```

Install Apigee Hybrid runtime


```
make apigee-runtime
```


# Cleaning up

Once you are finished experimenting with your ABM cluster, you can gracefully tear it down by running the following the commands.

##### Uninstall the ABM hybrid cluster using the bmctl tool
```
make uninstall-hybrid-cluster
```

##### Delete the VMS
```
make delete-vms
```