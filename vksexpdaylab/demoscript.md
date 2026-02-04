# VCF / VKS / VCFA Demo Runbook

---

## 1. Show Off Supervisor in VCA

- Supervisor overview, namespaces, all attributes

---

## 2. From CLI

Navigate to the lab directory and set context:

```bash
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
vcf context use supervisor:dev-c5545
```

Create guest cluster in `dev-c5545` namespace with an older K8s version (takes time to provision):

```bash
cat guest-cluster03.yaml
kubectl apply -f guest-cluster03.yaml
```

> **Note:** Using `v1.32.3---vmware.1-fips-vkr.2` intentionally so we can demo an upgrade later.

Show off the full cluster creation YAML with all available variables:

```bash
cat complete-cluster-example.yaml
```

Show off Supervisor API resources:

```bash
kubectl api-resources | grep -i "storageclasses\|virtualmachine\|virtualmachineimage\|osimage\|vmclass\|kubernetesreleases"
```

---

## 3. Show Off VCFA — Provider Portal

| Concept | What to Show |
|---|---|
| **Super Tenancy** | Organizations (Org) |
| **Tenancy** | Projects within an Org |
| **Region Quotas** | Resource limits per region |
| **Provider Networking** | Network configuration |
| **Connections** | OIDC, Supervisor registration |

---

## 4. Show Off VCFA — Consumer Portal

### Manage & Govern

- You have been given project `default-project` inside the `Broadcom` Org
- Guardrailing: regions, namespaces, namespace classes

### Build & Deploy

- Brings everything together for consumption — context and instances

---

## 5. vSphere Pods

Deploy the shopping app directly into the Supervisor namespace:

```bash
vcf context use supervisor:dev-c5545
kubectl apply -f shopping.yaml
```

> **If it fails:** Increase the `dev-c5545` namespace CPU limit to **30 GHz** in the vSphere Client, then retry:

```bash
kubectl delete -f shopping.yaml
kubectl apply -f shopping.yaml
```

Verify and access:

```bash
kubectl get svc
```

Hit the frontend `EXTERNAL-IP` in a browser.

---

## 6. Create a VM via VM Service

```bash
vcf context use supervisor:dev-c5545
cat oc-mysql2.yaml
kubectl apply -f oc-mysql2.yaml
```

---

## 7. Show Existing OpenCart App (VM + Container, Load Balanced)

### Database — VM on Supervisor

```bash
vcf context use supervisor:dev-c5545
kubectl get vm                 # existing oc-mysql VM
kubectl get svc                # look for TCP 3306 LB for the DB
```

### Frontend — Containers in Guest Cluster

```bash
vcf context use vks-01
kubectl get pods -n opencart
kubectl get svc -n opencart
```

Hit `http://10.1.11.4` in browser.

---

## 8. Upgrade Guest Cluster

```bash
vcf context use supervisor:dev-c5545
```

Upgrade `guest-cluster03` from `v1.32.3` → `v1.33.6`:

```bash
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
vcf context use supervisor:dev-c5545
cat guest-cluster03.yaml | grep certificate -A2 -B3
kubectl patch cluster guest-cluster03 -n dev-c5545 --type merge \
  -p '{"spec":{"topology":{"version":"v1.33.6---vmware.1-fips-vkr.2"}}}'
```

Monitor from VCFA:

```bash
vcf context use vcfa:dev-c5545:default-project
vcf cluster list               # shows "upgrading kr"
```

Also monitor rolling update progress in the **VCFA Consumer Portal**.

---

## 9. ArgoCD — test-xxx Namespace
Alter git repo and let argocd sup operator and argo instance deal with it

```bash
vcf context use supervisor:test-5plg6
kubectl get pods
argocd login 10.1.11.5     #admin   VMware123!VMware123!
argocd cluster list
argocd app list
argocd app get opencart-infra
```
in gitea - Change replicas to **4** in opencart-infra and watch ArgoCD sync

---

## 10. Verify Guest Cluster Upgrade & Connect

Once `guest-cluster03` upgrade completes (check VCFA Consumer Portal or `vcf cluster list`), register it and connect:

```bash
vcf context list
vcf context use vcfa:dev-xxxxx:default-project
# Token if prompted: 0lraViAN9alcyYTZ0KlAuqLqrvEqxsr3
```

Register the VCFA JWT authenticator for the upgraded cluster:

```bash
vcf cluster register-vcfa-jwt-authenticator guest-cluster03
```

Export the kubeconfig:

```bash
vcf cluster kubeconfig get guest-cluster03 --export-file ~/.kube/config
```

Create a VCF CLI context for the guest cluster:

```bash
vcf context create guest-cluster03 \
  --kubeconfig ~/.kube/config \
  --kubecontext vcf-cli-guest-cluster03-dev-xxxxx@guest-cluster03-dev-xxxxx
# → Select: cloud-consumption-interface
```

Refresh and switch to the new context:

```bash
vcf context refresh
vcf context list
vcf context use guest-cluster03
```

Verify the upgraded cluster is running the new K8s version:

```bash
kubectl get nodes
kubectl version
```
