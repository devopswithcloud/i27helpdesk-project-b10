* Create a k8s cluster 
* Run the OIDC Scripts 
* Configure the dockerhub secret and username oidc and service account details in github repo secrets
* In k8s cluster for deployment create the below namespaces
```bash
i27helpdesk-dev
i27helpdesk-test
i27helpdesk-stage
i27helpdesk-prod
```
* Before we deploy to gke in any environment , create the following environments in github actions 
```bash
dev
test
stage
prod
```