Show off Supervisor in VCA
===
sup, ns, all attributes

from CLI
===
- cd ~/Documents/Lab/shopping/vksdemo-main/vksexpdaylab/
- vcf context use supervisor:dev-c5545
create guest cluster in the dev-c5545 namespace with an older K8S version (v1.32.3---vmware.1-fips-vkr.2) as it takes long time
- cat guest-cluster03.yaml
- kubectl apply -f guest-cluster03.yaml
- show off api-resources. sc,vm,vmi,osimages,vmclass

Show off VCFA-Provider
===
- super tenancy (org)
- tenancy (project)
- region qutoes
- provider networking
- connections / OIDC / supervisor etc

Show off VCFA Consumer
===
MANAGE and GOVERN
- imagine you have been given project: 'default-project' tenancy inside 'Broadcom' ORG
- guardrailing: regions, namespace, namespace classes
BUILD and DEPLOY
- brings everything together for consumption - context and instances 



Show vSphere PODS
===
deploy shopping app directly into SUP ns >>
- vcf context use supervisor:dev-c5545
- kubectl apply -f shopping.yaml 
will fail make DEV namspace CPU limit up to 30-GHZ
- kubectl delete -f shopping.yaml >> apply
- kubectl get svc >> hit the frontend

Create VM in that namespace using vmservice
===
- vcf context use supervisor:dev-c5545
- kubectl apply -f oc-mysql2.yaml
- cat oc-mysql2.yaml

Show existing app Opencart (vm and container, all LB'd)
===
- vcf context use supervisor:dev-c5545
existing oc-mysql
- kubectl get vm
- kubectl get svc   // look for TCP3306 for LB for DB
drop into the guest cluster which is running the frontend...
- vcf context use vks-01
- kubectl get pods -n opencart
- kubectl get svc -n opencart (hit http://10.1.11.4 in browser)

Upgrade the guest-cluster03
===
vcf context use supervisor:dev-c5545
upgrade cluster from 1.32.3 to 1.33.6
kubectl patch cluster guest-cluster03 -n dev-c5545 --type merge \
  -p '{"spec":{"topology":{"version":"v1.33.6---vmware.1-fips-vkr.2"}}}'
vcf context use vcfa:dev-c5545:default-project
vcf cluster list (upgrading kr) >> see also monitor in VCFA Consumer

- Then go over to the test space and show off the Argo CD staff change replicas to 4
-


Then go over to the test space and show off the Argo CD staff change replicas to 4

 
