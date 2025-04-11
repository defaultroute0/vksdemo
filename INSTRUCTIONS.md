# VKS Demo Commands
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
````
New-Alias -Name "k" "kubectl"
New-Alias -Name "kg" "kubectl get"
New-Alias -Name "kd" "kubectl describe"
New-Alias -Name "kaf" "kubectl apply -f"
New-Alias -Name "kc" "kubectl create"
New-Alias -Name "kdel" "kubectl delete --force"
New-Alias -Name "ke" "kubectl delete --force"
New-Alias -Name "kr" "kubectl run"
````


## Poke around, and show off the ns01 in vcenter
------
````
kubectl-vsphere login --server=https://10.80.0.2 --insecure-skip-tls-verify --vsphere-username administrator@vsphere.local
kubectl config get-contexts
kubectl config use-context 10.80.0.2
kubectl create ns ns01
kubectl describe ns ns01
kubectl get sc
kubectl get tkr
kubectl get virtualmachineclass
````

Make sure namespace in vcenter has permission and content library, vm classes etc

## Deploy Guest Cluster
-------
Get this started while you show stuff in SUP cluster as it takes a while
````
kubectl apply -f .\guest-cluster01.yaml -n ns01
````

Now back to SUP Cluster....

## Deploy into SUP cluster namespace 
---
Deploy something into the SUP cluster into ns01 namespace controls / config to show  PODS running inside hypervisor directly
````
kubectl apply -f .\shopping.yaml -n ns01
kubectl get svc -n ns01
kubectl get svc -n ns01 -o wide
kubectl get pods -n ns01 -o wide

````

Goto the External LB address listed there in browser!

Jump over to NSX explain the NCP
### Break the connection to backend DB with netpol (via NCP) and show off in DFW
````
kubectl apply -f netpolexample.yaml -n ns01
kubectl delete -f netpolexample.yaml -n ns01
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
kubectl-vsphere logout
kubectl-vsphere login --server=https://10.80.0.2 --insecure-skip-tls-verify --tanzu-kubernetes-cluster-name guest-cluster01 --vsphere-username administrator@vsphere.local
kubectl config use-context guest-cluster01
kubectl get nodes
kubectl create ns shopping
kubectl label --overwrite ns shopping pod-security.kubernetes.io/enforce=privileged
kubectl apply -f .\shopping.yaml -n shopping
kubectl get all -n shopping
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
