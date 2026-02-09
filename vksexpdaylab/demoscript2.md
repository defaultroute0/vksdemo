# VCF / VKS / VCFA Demo Runbook (with VKS vs DIY Talking Points)

> This is the same demo flow as `demoscript.md` with **verified commentary** added as `> SAY:` callouts. These are subtle one-liners to drop while commands are running — they highlight why VKS matters vs. managing K8s yourself on bare metal.

## Prerequisites: Download Demo Files

**From the lab console browser:**

1. Open Firefox and navigate to: `https://github.com/defaultroute0/vksdemo`
2. Click the green **Code** button → **Download ZIP**
3. Save to `~/Downloads/`
4. Extract to the Lab directory:

```bash
cd ~/Documents/Lab
unzip ~/Downloads/vksdemo-main.zip
ls ~/Documents/Lab/vksdemo-main/vksexpdaylab/
```

You should see: `guest-cluster03.yaml`, `oc-mysql2.yaml`, `complete-cluster-example.yaml`, `setup.sh`, `teardown.sh`, etc.

> **Note:** All commands in this runbook assume files are at `~/Documents/Lab/vksdemo-main/`. If you cloned via `git clone` instead of downloading the ZIP, the path is the same — just rename the folder if needed.

---

<br>

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
also turn nsx edge vm 2 off to save CPU
```

---

<br>

## 1. Show Off Supervisor in VCA

- Supervisor overview, namespaces, all attributes

---

<br>

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

> **SAY:** "That one YAML declares the entire cluster — K8s version, node sizes, networking, storage, certificate rotation. On bare metal, that's Ansible playbooks, custom scripts, and hoping nothing drifts between what you documented and what's actually running."

> **Note:** "Using `v1.32.3---vmware.1-fips-vkr.2` intentionally so we can demo an upgrade later."

Show off the full cluster creation YAML with all available variables:

```bash
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
cat complete-cluster-example.yaml
```

Talk about the supervisor:

```bash
vcf context list --wide
vcf context use supervisor:$DEV_NS
kubectl get nodes
kubectl get clusters

vcf context use supervisor:$TEST_NS
kubectl get nodes
kubectl get clusters
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
kubectl describe kr v1.33.6---vmware.1-fips-vkr.2
kubectl get osimages | grep 1.33.6
```

> **SAY (on `kubectl get sc` / `kubectl get vmclass`):** "Notice the developer can only see storage classes and VM sizes the admin bound to this namespace. The Supervisor API enforces that at admission — no OPA, no manual RBAC policies needed."

> **SAY (on `kubectl get kr`):** "Every VKr bundles the CNI, CSI, CoreDNS, containerd, etcd — all version-locked and tested together. On bare metal, you're upgrading those five components independently and hoping they still talk to each other."

A VKr/ (now labeled kr) is a curated Kubernetes distribution release published by Broadcom. It includes:
- A specific Kubernetes version
- VM image (OVA) stored in a Content Library
- Bundled core packages (Antrea CNI, kapp-controller, secretgen-controller, etc.)
- Security patches and CVE fixes

---

<br>

## 3. Show Off VCFA — Provider Portal

| Concept | What to Show |
|---|---|
| **Super Tenancy** | Organizations (Org) |
| **Tenancy** | Projects within an Org |
| **Region Quotas** | Resource limits per region |
| **Provider Networking** | Network configuration |
| **Connections** | OIDC, Supervisor registration |

> **SAY (on Orgs / Connections):** "Each org connects its own identity provider — Okta, Azure AD, on-prem ADFS, whatever they use. On DIY multi-tenant K8s, everyone shares one OIDC config or you're running separate clusters with no unified management layer."

---

<br>

## 4. Show Off VCFA — Consumer Portal

### Manage & Govern

- You have been given project `default-project` inside the `Broadcom` Org
- Guardrailing: regions, namespaces, namespace classes

### Build & Deploy

- Brings everything together for consumption — context and instances

---

<br>

## 5. vSphere Pods

Deploy the shopping app directly into the Supervisor namespace:

```bash
cd ~/Documents/Lab/vksdemo-main/
vcf context use supervisor:$DEV_NS
kubectl apply -f shopping.yaml
```

> **SAY:** "These pods are running in CRX micro-VMs directly on the hypervisor — each one gets its own kernel, its own memory space. On bare metal, every pod on a node shares the same kernel. A container escape here lands you in a minimal paravirtualized VM, not on a shared host."

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

<br>

## 6. Create a VM via VM Service

```bash
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
vcf context use supervisor:$DEV_NS
cat oc-mysql2.yaml
kubectl apply -f oc-mysql2.yaml
```

---

<br>

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

> **SAY:** "The database is a VM, the frontend is containers — both managed through the same Supervisor API, both getting load balancer VIPs from the same NSX infrastructure. On bare metal, that's two separate management planes you're stitching together yourself."

---

<br>

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
watch "kubectl get machines | grep guest"
```

> **SAY (on patch):** "One command. Rolling update, PDB-aware, back-in-time protection included. On bare metal this is drain, upgrade, uncordon, repeat per node — and you're crossing your fingers the CNI version still matches."

> **SAY (while watching machines):** "It's replacing each node as a fresh VM from the new VKr image — no in-place patching, no leftover state from the old version. If this fails mid-way, it rolls back the affected nodes automatically. There's no voluntary downgrade though — it's forward-only by design."

Monitor from VCFA:

```bash
vcf context use vcfa:$DEV_NS:default-project
vcf cluster list               # shows "upgrading kr"
```

Also monitor rolling update progress in the **VCFA Consumer Portal**.

---

<br>

## 9. ArgoCD — test-xxx Namespace
Alter git repo and let argocd sup operator and argo instance deal with it

```bash
vcf context use supervisor:$TEST_NS
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
cat ../../argocd-instance.yaml
kubectl get pods
argocd login 10.1.11.5
 #admin   VMware123!VMware123!

argocd cluster list
argocd app list
argocd app get opencart-infra
```

> **SAY:** "The ArgoCD operator was enabled as a Supervisor Service — one toggle in vSphere Client. Each namespace gets its own instance from a single YAML. On bare metal you're helm-installing ArgoCD, managing its Redis, its certs, its ingress, its upgrades — all yourself."

```
Supervisor (cluster-wide)
│
├── ArgoCD Operator (from Supervisor Service tile)
│     - Registers kind: ArgoCD CRD
│     - Watches all namespaces for ArgoCD CRs
│     - Pulls Broadcom-validated container images
│     - Does NOT run any ArgoCD server itself
│
├── test-xxxxx namespace
│     └── kind: ArgoCD CR applied (argocd-instance.yaml)
│           └── Operator deploys:
│               ├── argocd-server (UI + API)
│               ├── argocd-repo-server (Git cloning)
│               ├── argocd-application-controller (sync engine)
│               ├── argocd-redis (caching)
│               ├── Service type: LoadBalancer (external VIP)
│               └── Secret: argocd-initial-admin-secret
│
├── dev-xxxxx namespace
│     └── (no ArgoCD CR = no instance here)
│
└── prod-xxxxx namespace
      └── (could deploy another independent ArgoCD instance)
```


in gitea - Change replicas to **4** in opencart-infra and watch ArgoCD sync

---

<br>

## 10. Verify Guest Cluster Upgrade & Connect

Once `guest-cluster03` upgrade completes (check VCFA Consumer Portal or `vcf cluster list`), download the kubeconfig and connect:

1. **VCFA Consumer Portal** → your project → click on `guest-cluster03` → **Download Kubeconfig**
2. Save it to `~/Downloads/guest-cluster03-kubeconfig.yaml`

OR

```bash
vcf context use supervisor:$DEV_NS
kubectl get secret guest-cluster03-kubeconfig -o jsonpath='{.data.value}' | /usr/bin/base64 -d > ~/Downloads/guest-cluster03-kubeconfig.yaml
```

Use it directly:

```bash
vcf context use supervisor:$DEV_NS
kubectl --kubeconfig ~/Downloads/guest-cluster03-kubeconfig.yaml get nodes
  # make sure upgrade has fininshed first
kubectl -n "$DEV_NS" patch cluster guest-cluster03 --type merge -p '{"spec":{"topology":{"workers":{"machineDeployments":[{"name":"guest-cluster03-nodepool-7khv","class":"node-pool","replicas":2}]}}}}'
kubectl -n "$DEV_NS" get machinedeployments
kubectl -n "$DEV_NS" get machines
kubectl --kubeconfig ~/Downloads/guest-cluster03-kubeconfig.yaml version
kubectl --kubeconfig ~/Downloads/guest-cluster03-kubeconfig.yaml create ns shopping
kubectl --kubeconfig ~/Downloads/guest-cluster03-kubeconfig.yaml label ns shopping pod-security.kubernetes.io/enforce=privileged
kubectl --kubeconfig ~/Downloads/guest-cluster03-kubeconfig.yaml apply -f ~/Documents/Lab/vksdemo-main/shopping.yaml -n shopping
kubectl --kubeconfig ~/Downloads/guest-cluster03-kubeconfig.yaml get svc -n shopping
```

> **SAY (on PSS label):** "We had to explicitly label that namespace as privileged. The ClusterClass default is `enforce: restricted` — so unless someone deliberately weakens it, every namespace blocks privileged pods. On bare metal, PSS is off unless someone remembers to turn it on — and they usually don't."

Show what a vanilla cluster includes:
- k8s controllers, and core packages: storage drivers, auth, cni, velero, secret management, security patches and CVE's

```bash
kubectl --kubeconfig ~/Downloads/guest-cluster03-kubeconfig.yaml get ns

kubectl get kr
kubectl describe kr v1.33.6---vmware.1-fips-vkr.2 | grep -e Boot -e Name
kubectl get osimages | grep 1.33.6
```

> **SAY (on `get ns`):** "All those namespaces — Antrea, CSI, Pinniped, kapp-controller — came with the cluster. You didn't install any of them. On DIY, each one is a separate Helm chart you maintain, patch, and troubleshoot when it breaks at 3am."

---

<br>

## Appendix: Setup & Teardown Scripts

One-shot scripts to create or delete everything. Both require `DEV_NS` to be set.

> **Before setup:** Ensure the `$DEV_NS` namespace CPU limit is set to **30 GHz** in vSphere Client.

**Create everything:**

```bash
export DEV_NS=dev-XXXXX
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
./setup.sh
```

**Delete everything:**

```bash
export DEV_NS=dev-XXXXX
cd ~/Documents/Lab/vksdemo-main/vksexpdaylab/
./teardown.sh
```

| Script | What It Does |
|---|---|
| `setup.sh` | Deploys guest-cluster03, shopping app, oc-mysql2 VM. Waits for all to be ready. |
| `teardown.sh` | Deletes guest-cluster03, shopping app, oc-mysql2 VM. Waits for full cleanup. |
