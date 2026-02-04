# VCF / VKS / VCFA Demo Runbook

## Lab Variables

> **Set these once per lab deployment.** The namespace IDs are dynamically generated and change each time.

| Variable | Value | Where to Find |
|---|---|---|
| `DEV_NS` | `dev-_____` | VCFA Consumer Portal → Projects, or `vcf context list` |
| `TEST_NS` | `test-_____` | VCFA Consumer Portal → Projects, or `vcf context list` |

```bash
# Run these at the start of your session:
export DEV_NS=dev-XXXXX
export TEST_NS=test-XXXXX
```

---

## 1. Show Off Supervisor in VCA

- Supervisor overview, namespaces, all attributes

---

## 2. From CLI

Navigate to the lab directory and set context:

```bash
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
vcf context use supervisor:$DEV_NS
```

Create guest cluster in `$DEV_NS` namespace with an older K8s version (takes time to provision):

```bash
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
cat guest-cluster03.yaml
kubectl apply -f guest-cluster03.yaml
```

> **Note:** "Using `v1.32.3---vmware.1-fips-vkr.2` intentionally so we can demo an upgrade later."

Show off the full cluster creation YAML with all available variables:

```bash
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
cat complete-cluster-example.yaml
```

Show off Supervisor API resources:

```bash
vcf context use supervisor:$DEV_NS
kubectl api-resources | grep -i "storageclasses\|virtualmachine\|virtualmachineimage\|osimage\|vmclass\|kubernetesreleases"
kubectl get sc
kubectl get vmclass
kubectl get vm
kubectl get vmi
kubectl get kr
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
cd ~/Documents/Lab/vksdemo-main/
vcf context use supervisor:$DEV_NS
kubectl apply -f shopping.yaml
```

> **If it fails:** "Increase the `$DEV_NS` namespace CPU limit to **30 GHz** in the vSphere Client, then retry:"

```bash
cd ~/Documents/Lab/vksdemo-main/
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
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
vcf context use supervisor:$DEV_NS
cat oc-mysql2.yaml
kubectl apply -f oc-mysql2.yaml
```

---

## 7. Show Existing OpenCart App (VM + Container, Load Balanced)

### Database — VM on Supervisor

```bash
vcf context use supervisor:$DEV_NS
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
vcf context use supervisor:$DEV_NS
```

Upgrade `guest-cluster03` from `v1.32.3` → `v1.33.6`:

```bash
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
vcf context use supervisor:$DEV_NS
cat guest-cluster03.yaml | grep certificate -A2 -B3
kubectl patch cluster guest-cluster03 -n $DEV_NS --type merge \
  -p '{"spec":{"topology":{"version":"v1.33.6---vmware.1-fips-vkr.2"}}}'
```

Monitor from VCFA:

```bash
vcf context use vcfa:$DEV_NS:default-project
vcf cluster list               # shows "upgrading kr"
```

Also monitor rolling update progress in the **VCFA Consumer Portal**.

---

## 9. ArgoCD — test-xxx Namespace
Alter git repo and let argocd sup operator and argo instance deal with it

```bash
vcf context use supervisor:$TEST_NS
kubectl get pods
argocd login 10.1.11.5     #admin   VMware123!VMware123!
argocd cluster list
argocd app list
argocd app get opencart-infra
```
in gitea - Change replicas to **4** in opencart-infra and watch ArgoCD sync

---

## 10. Verify Guest Cluster Upgrade & Connect

Once `guest-cluster03` upgrade completes (check VCFA Consumer Portal or `vcf cluster list`), download the kubeconfig and connect:

1. **VCFA Consumer Portal** → your project → click on `guest-cluster03` → **Download Kubeconfig**
2. Save it to `~/Downloads/guest-cluster03-kubeconfig.yaml`

Use it directly:

```bash
kubectl --kubeconfig ~/Downloads/guest-cluster03-kubeconfig.yaml get nodes
kubectl --kubeconfig ~/Downloads/guest-cluster03-kubeconfig.yaml version
```
