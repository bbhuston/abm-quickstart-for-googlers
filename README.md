# Provisioning an Anthos bare metal environment on GCP

##### Set your GCP Project ID
```
export PROJECT_ID=<Enter your Anthos bare metal GCP Project ID>
```

##### Set default GCP Project
```
make set-default-gcp-project
```

##### Enable GCP APIs
```
make enable-gcp-apis
```

##### Configure IAM permissions
```
make configure-iam-permissions
```

##### Create VMs
```
make create-vms
```

##### Prepare a ABM hybrid cluster
```
make prepare-hybrid-cluster
```