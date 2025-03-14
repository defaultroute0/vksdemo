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

Make sure namespace in vcenter has permission and content library

Deploy Guest Cluster
````
kubectl apply -f .\guest-cluster01.yaml -n ns01
````

Deploy something into the SUP cluster into ns01 namespace  to show   PODS running inside hypervisor directly
````
kubectl apply -f .\shopping.yaml -n ns01
kubectl get svc -n ns01
````
Goto the External LB address listed there in browser!

Deploy something into the SUP cluster into ns01 namespace
````
kubectl apply -f .\shopping.yaml -n ns01
kubectl get svc -n ns01
````

Deploy something into the GUEST cluster into ns01 namespace
````
kubectl-vsphere logout
kubectl-vsphere login --server=https://10.80.0.2 --insecure-skip-tls-verify --tanzu-kubernetes-cluster-name guest-cluster01 --vsphere-username administrator@vsphere.local
kubectl create ns shopping
kubectl label --overwrite ns shopping pod-security.kubernetes.io/enforce=privileged
kubectl apply -f .\shopping.yaml -n shopping
kubectl get all -n ns01
````

Can also go to External LB listed in svcs NSX fired up to show shopping is up in guest cluster



Note
Deploying into guest cluster need to label the ns to relax security
https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere-supervisor/8-0/using-tkg-service-with-vsphere-supervisor/managing-security-for-tkg-service-clusters/configure-psa-for-tkr-1-25-and-later.html
