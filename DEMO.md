# VKS Demo Commands (VCF9)
========

# DEMO1

## Optional Resume LOGIN if you come back
````
vcf context refresh
VMware123!VMware123!
````

## Show Supervisor Management in vca
- how sup is configured.  TABS in SUPERVISOR MANAGEMRNT
- how we create a ns (ns02)
- show how this is rendered in nsx quickly (vpc)

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
 

- Now back to SUP Cluster
- Show ns01 >> Configure Resource and Object Limits

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
Goto the vca ns01 >> RESOURCES tab 

## Map the objects created back to the supervisor VPC networking setup
GOTO >> SUPERVISOR MANAGEMENT >>  NS01 >> CONFIGURE >> General

## Show the External VPC Block(s) / POD CIDR consumed by the ext svc, svc, pods  in NS01
````
kubectl get pods -n ns01 -o wide    ##things in whole ns can talk via TGW range, 172.16.100 range
kubectl get svc -n ns01     ##things in ns - internal svc 10.96.0.0 and external svc 10.1.0.x
kubectl get pod -A -o wide | grep -e 200    ##internal backend things which can only talk witin their special system namespace  
````

## Jump over to NSX explain the NCP
(VPC >> Network Services >> NSX Load Balancer))


# DEMO2

## Create a VM, via SUP declaritive API
We can create a VM via kind: VirtualMachine
````
cat mydemovm.yaml
kubectl apply -f mydemovm.yaml -n ns01
````
## Break the connection to backend DB with netpol (via NCP) and show off in DFW, the delete it to restore app connectivity
````
kubectl apply -f netpolexample.yaml -n ns01
kubectl delete -f netpolexample.yaml -n ns01
````
Look in the VPC E/W Rules

## Apply 5 different netpol's
then apply a variety of netpol examples to the frontend of the app, and go and find the 5 line items in the DFW to see how each method renders out from yaml to DFW. 
This can be left on as it allows app workings
````
kubectl apply -f shoppingingressnetpol.yaml -n ns01
kubectl describe netpol -n ns01
````

## Deploy a Guest CLuster via VKS
````
k apply -f guest-cluster02.yaml -n ns01
vcf cluster list -n ns01
````

## Deploy something into the GUEST cluster into ns01 namespace
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


## Cleanup
````
vcf context use mysup:ns01
k delete -f shopping.yaml -f shoppingingress.yaml -f shoppingingressnetpol.yaml -f netpolexample.yaml -f mydemovm.yaml -n ns01
k delete -f guest-cluster02.yaml -n ns01
vcf context delete guest-cluster02:guest-cluster02 -y
vcf context delete guest-cluster02 -y
````
## Build
````
vcf context use mysup:ns01
k apply -f shopping.yaml -f shoppingingress.yaml -f shoppingingressnetpol.yaml -f mydemovm.yaml -n ns01
k apply -f guest-cluster02.yaml -n ns01
vcf cluster list -n ns01
````
