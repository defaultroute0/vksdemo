kubectl-vsphere login --server=https://10.80.0.2 --insecure-skip-tls-verify --vsphere-username administrator@vsphere.local
kubectl config get-contexts
kubectl config use-context 10.80.0.2
kubectl describe ns ns01
kubectl get sc
kubectl get tkr
kubectl get virtualmachineclass
kubectl apply -f .\ryancluster01.yaml
kubectl apply -f .\sandercluster01.yaml
kubectl-vsphere login
kubectl-vsphere login --server=https://10.80.0.2 --insecure-skip-tls-verify --vsphere-username administrator@vsphere.local
kubectl-vsphere login --server=https://10.80.0.2 --insecure-skip-tls-verify --tanzu-kubernetes-cluster-name ryan-cluster01 --vsphere-username administrator@vsphere.local 
---
Deploying into guest cluster need to label the ns to relax security
https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere-supervisor/8-0/using-tkg-service-with-vsphere-supervisor/managing-security-for-tkg-service-clusters/configure-psa-for-tkr-1-25-and-later.html
