Show off Supervisor in VCA


from CLI:  supervisor:dev-c5545 namespace...
- create guest cluster in the DEV name space with an older K8S version (v1.32.3---vmware.1-fips-vkr.2) as it takes long time
- show off api-resources. sc,vm,vmi,osimages,vmclass


Show off VCFA-Provider
- super tenancy (org)
- tenancy (project)
- region qutoes
- provider networking
- connections / OIDC / supervisor etc


Show off VCFA
MANAGE and GOVERN
- imagine you have been given project: 'default-project' tenancy inside 'Broadcom' ORG
- guardrailing: regions, namespace, namespace classes
BUILD and DEPLOY
- brings everything together for consumption - context and instances 



SHOW vSphere PODS
- deploy shopping app directly into sup >>
- vcf context use supervisor:dev-c5545
- kubectl apply -f shopping.yaml 
- will fail make DEV namspace CPU limit up to 30-GHZ
- kubectl delete -f shopping.yaml >> reapply
- kubectl get svc >> hit the frontend

  
- create VM in that name space with a YAML file
-
- Download to keep comic file from VCF automation log into the guest Costa change the permissions and deploy the shopping card app
-
- Show off the load balancing
-
- Then go over to the test space and show off the Argo CD staff change replicas to 4
-
- kubectl apply -f shopping.yaml
- they wont come up... describe pod.
- now make DEV namspace CPU limit up to 30-GHZ


create VM in that name space with a YAML file

Download to keep comic file from VCF automation log into the guest Costa change the permissions and deploy the shopping card app

Show off the load balancing

Then go over to the test space and show off the Argo CD staff change replicas to 4

kubectl patch cluster guest-cluster01 -n dev-c5545 --type merge \
  -p '{"spec":{"topology":{"version":"v1.33.6---vmware.1-fips-vkr.2"}}}'

v1.32.3---vmware.1-fips-vkr.2
v1.33.6---vmware.1-fips-vkr.2
