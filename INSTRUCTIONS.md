# VKS Demo Commands (VCF9)
========

- Run from hollowconsole in lab
- Install Cygwin as there is no linux box ;(
- Alias Up... make your life easier! 

## Linux 
----------
````
alias k=kubectl
alias kg="kubectl get"
alias kd="kubectl describe"
alias kaf="kubectl apply -f"
alias kc="kubectl create"
alias kdel="kubectl delete --force"
alias ke="kubectl edit"
alias kr="kubectl run"
export do="--dry-run=client -oyaml"
````


## Windows
------
notepad.exe $PROFILE

add this

````
function k    { & kubectl @args }
function kg   { & kubectl get @args }
function kd   { & kubectl describe @args }
function kaf  { & kubectl apply -f @args }
function kc   { & kubectl create @args }
function kdel { & kubectl delete --force @args }
function ke   { & kubectl exec @args }
function kr   { & kubectl run @args }
````
Save the Profile and Restart PowerShell.
or do ". $PROFILE"

This way, when you type kg, it will invoke kubectl get as expected.

## Grab the yaml and *.sh
````
Download the zip file from homepage in vksdemo for the yaml and sh scripts
````

## Install new vcf-cli k8s wrapper
------
````
chmod +x install-new-vcf-cli.sh
./install-new-vcf-cli.sh
vcf context list    //to test cli thing works
# maybe need // sudo snap install --classic kubectl
````

add the plugins
````
vcf plugin group search
vcf plugin install --group vmware-vcfcli/essentials
vcf plugin group get vmware-vcfcli/essentials
vcf plugin list
````

Because trust chain doesnt seem intact in this lab, lets feed the cert returned from vca into the chain
````
openssl s_client -connect 10.1.0.2:443 -showcerts </dev/null 2>/dev/null | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' > ~/hol/ca/full-chain.crt
vcf context create --endpoint 10.1.0.2:443 -username administrator@wld.sso --ca-certificate ~/hol/ca/full_chain.crt
  create 'mysup'
vcf context list
vcf context use mysup:ns01
#OLD WAY: kubectl-vsphere login --server=https://10.1.0.2 --insecure-skip-tls-verify --vsphere-username administrator@wld.sso
````

## Namespace in vCenter
````
create the ns 'ns01' in vca
Make sure namespace in vcenter has permission and content library, vm classes (best-effort-small), storage class etc
````

## Optional Resume LOGIN if you come back
````
vcf refresh context
VMware123!VMware123!
````

## Deploy Guest Cluster
-------
Get this started while you show stuff in SUP cluster as it takes a while
````
cd ~/Downloads/vksdemo-vcf9/
vcf cluster create -f guest-cluster01.yaml
vcf cluster list -n ns01
````


## Poke around, and show off the ns01 in vcenter
------
````
kubectl config get-contexts
kubectl config use-context mysup:ns01
kubectl api-resources 
kubectl api-resources | grep -e vmware 
kubectl get nodes
kubectl describe ns ns01
kubectl get sc
kube get tkr
vcf kubernetes-release get
kubectl get virtualmachineclass
kubectl get vmi
````
 

Now back to SUP Cluster....

## Deploy into SUP cluster namespace 
---
Deploy something into the SUP cluster into ns01 namespace controls / config to show  PODS running inside hypervisor directly
````
kubectl apply -f shopping.yaml -n ns01
kubectl get svc -n ns01
kubectl get svc -n ns01 -o wide
kubectl get pods -n ns01 -o wide
````

Goto the External LB address listed there in browser!

## Map the objects created back to the supervisor VPC networking setup

GOTO >> SUPERVISOR MANAGEMENT >>  NS01 >> CONFIGURE >> General

### Show the External VPC Block(s) / POD CIDR consumed by the ext svc, svc, pods  in NS01
````
kubectl get pods -n ns01 -o wide    ##things in whole ns can talk via TGW range, 172.16.100 range
kubectl get svc -n ns01     ##things in ns - internal svc 10.96.0.0 and external svc 10.1.0.x
kubectl get pod -A -o wide | grep -e 200    ##internal backend things which can only talk witin their special system namespace  
````

Jump over to NSX explain the NCP
(VPC >> Network Services >> NSX Load Balancer))

### Break the connection to backend DB with netpol (via NCP) and show off in DFW, the delete it to restore app connectivity
````
kubectl apply -f netpolexample.yaml -n ns01
kubectl delete -f netpolexample.yaml -n ns01
````
Look in the VPC E/W Rules

### Apply 5 different netpol's
then apply a variety of netpol examples to the frontend of the app, and go and find the 5 line items in the DFW to see how each method renders out from yaml to DFW. 
This can be left on as it allows app workings
````
kubectl apply -f shoppingingressnetpol.yaml -n ns01
kubectl describe netpol -n ns01
````


## Secure Access to app
- Install Contour as a Sup Service
- Add envoy endpoint IP address into lab DNS as per below CN (see insitu lab guide)
- Create a TLS Key pair
- Create an Ingress and allow contour to talk to namespace pod frontend (pinhole override for zero trust namespace-namespace comms is blocked by default) 
````
openssl req -x509 -nodes -days 900 \
-newkey rsa:2048 \
-out shopping-ingress-secret.crt \
-keyout shopping-ingress-secret.key \
-subj "/CN=shoppingingress.vcf.sddc.lab/O=shopping-ingress-secret"

kubectl create secret tls shopping-ingress-secret --key shopping-ingress-secret.key --cert shopping-ingress-secret.crt -n ns01
kubectl apply -f shoppingingress.yaml -f shoppingingressnetpol.yaml -n ns01
````

Deploy something into the GUEST cluster into ns01 namespace
-----
````
vcf context create guest-cluster01 --endpoint 10.1.0.2:443 --username administrator@wld.sso --ca-certificate ~/hol/ca/full_chain.crt --workload-cluster-name guest-cluster01 --workload-cluster-namespace ns01 --type k8s
vcf context use guest-cluster01:guestcluster01
   this will take us into the guest-cluster01 deployed into the sup cluster's namespace 'ns01'
kubectl get nodes
kubectl create ns shopping
kubectl label --overwrite ns shopping pod-security.kubernetes.io/enforce=privileged
kubectl apply -f shopping.yaml -n shopping
kubectl get all -n shopping
kubectl get svc -A | grep -e external
````

Install Antrea Interworking stuff
--------

*WIP: Needs to be manually built or published in SE Field Labs. tried doing it via Advanced SE Fielf Labs Template, needs antrea ent binaries, right vDefend lic. SSL certs made, needs Linux box to use antreansxctl NSX-Antrea interworking integration and gen the certs for principle identies etc*

Installation doc here:
[Prerequisites for Registering an Antrea Kubernetes Cluster to NSX](https://techdocs.broadcom.com/us/en/vmware-cis/nsx/vmware-nsx/4-2/administration-guide/integration-of-kubernetes-clusters-with-antrea-cni/registering-an-antrea-kubernetes-cluster-to-nsx/prerequisites-for-registering-an-antrea-kubernetes-cluster-to-nsx.html "Prerequisites for Registering an Antrea Kubernetes Cluster to NSX")

````
kubectl get pod -n kube-system -l component=antrea-controller
kubectl exec -it antrea-controller-<AsAbove> -n kube-system -- antctl version
kubectl get pods -n shopping | grep -e antrea
kubectl get pods -n shopping --show-labels
kubectl get acnp
kubectl describe acnp da803eb7-f151-4e59-9663-229f6eb068ce   <<replace with you policy id>>
kubectl describe acnp da803eb7-f151-4e59-9663-229f6eb068ce | grep -e Action -e From: -e To: -e Protocol -e Block -e Port -e Cidr -e Ingress: -e Egress:
````


Can also go to External LB listed in svcs NSX fired up to show shopping is up in guest cluster



*Note
Deploying into guest cluster need to label the ns to relax security*
https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere-supervisor/8-0/using-tkg-service-with-vsphere-supervisor/managing-security-for-tkg-service-clusters/configure-psa-for-tkr-1-25-and-later.html


## Cleanup/Build
````
vcf context use mysup:ns01
k delete -f shopping.yaml -f shoppingingress.yaml -f shoppingingressnetpol.yaml -f netpolexample.yaml -n ns01
k delete -f guest-cluster02.yaml -n ns01
vcf context delete guest-cluster02:guest-cluster02 -y
vcf context delete guest-cluster02 -y
---
vcf context use mysup:ns01
k apply -f shopping.yaml -f shoppingingress.yaml -f shoppingingressnetpol.yaml -n ns01
k apply -f guest-cluster02.yaml -n ns01
vcf cluster list -n ns01
````

