kubectl-vsphere login --server=https://10.80.0.2 --insecure-skip-tls-verify --vsphere-username administrator@vsphere.local
kubectl config get-contexts
kubectl config use-context 10.80.0.2
kubectl describe ns ns01
kubectl get sc
kubectl get tkr
kubectl get virtualmachineclass
kubectl apply -f .\ryancluster01.yaml
kubectl apply -f .\sandercluster01.yaml
