# VKS CAPI Admission Webhook Troubleshooting Guide

**Environment:** VCF 9 / vSphere Supervisor
**Issue:** CAPI errors when creating or upgrading VKS clusters after VKS version upgrade
**Last Updated:** 2026-02-17

---

## TL;DR

After installing VKS 3.4.0 on the Supervisor, cluster creation fails for ~30-60 minutes with `"variable is not defined"` webhook errors. This happens because the CAPI controllers still have stale caches and certificates from the previous VKS version.

**Just run the script** — it handles everything automatically:
```bash
./vks-capi-webhook-troubleshoot.sh --fix
```

The script will:
1. Run 12 diagnostic checks against the Supervisor
2. Try to restart the controllers via `kubectl` from your current context
3. If `kubectl` is blocked (it usually is), automatically SSH into a Supervisor CP VM to do the restarts
4. Verify everything is healthy afterward

**If the script says `VariablesReconciled=False`** after the fix, run the cert regeneration mode:
```bash
./vks-capi-webhook-troubleshoot.sh --fix-cert
```

**Or just wait ~60 minutes** — it self-resolves as the controllers cycle.

**Prevention:** Install VKS 3.4.0 at least 60 minutes before students create clusters.

---

## Symptom

After uploading and installing a new VKS version (e.g., 3.4.0 via `3.4.0-package.yaml`) on the Supervisor, attempting to create a VKS cluster (via VCFA wizard or kubectl) within the next 30-60 minutes returns:

```
admission webhook "capi.mutating.tanzukubernetescluster.run.tanzu.vmware.com" denied the request:
Cluster and variable validation failed:
  [spec.topology.variables[kubernetes] ... variable is not defined,
   spec.topology.variables[vmClass] ... variable is not defined,
   spec.topology.variables[storageClass] ... variable is not defined]
```

**In plain English:** You asked the system to create a Kubernetes cluster with certain settings (like VM size, storage type, and K8s version), but a gatekeeper (the "admission webhook") is rejecting your request because it doesn't recognize those settings. It's looking at an outdated list of what's allowed.

---

## What's Happening Under the Hood

### Background: How VKS Cluster Creation Works

When you create a Kubernetes cluster through VCFA (or `kubectl`), the request goes through several layers on the Supervisor:

1. **You submit a Cluster manifest** — a YAML document describing what you want (K8s version, VM size, storage, etc.)
2. **CAPI admission webhooks validate it** — before the cluster is created, webhooks check that your manifest's variables (`vmClass`, `storageClass`, `kubernetes`) match the **ClusterClass schema** (a template that defines what variables are valid)
3. **If validation passes**, CAPI controllers create the VMs, install Kubernetes, and wire up networking
4. **If validation fails**, you get the `"variable is not defined"` error — the webhook rejected your request

**Key concepts for beginners:**

- **CAPI** (Cluster API) — the framework that automates creating and managing Kubernetes clusters on vSphere. Think of it as the "cluster factory."
- **Webhook** — a gatekeeper that intercepts API requests and validates them before they're processed. Like a bouncer checking IDs.
- **ClusterClass** — a versioned template (e.g., `builtin-generic-v3.4.0`) that defines what variables a cluster can use. Think of it as a form template — if you fill in a field that doesn't exist on the form, the webhook rejects it.
- **Controller** — a background process (running as a Kubernetes pod) that watches for changes and acts on them. For example, the CAPI controller creates VMs when you submit a cluster manifest.
- **Reconciliation** — Kubernetes constantly compares "desired state" (what you asked for) with "actual state" (what exists). When they differ, controllers "reconcile" by making changes to match.

### Why It Breaks After a VKS Upgrade

Installing a new VKS version triggers a cascade of reconciliation on the Supervisor. Three things can go wrong, often overlapping:

### 1. RuntimeSDK Feature Flag Race Condition (KB 392756)

The kapp-controller reconciles VKS packages in parallel. The `runtime-extension` package tries to create `extensionconfig` resources **before** the RuntimeSDK feature flag is initialized. The CAPI admission webhook blocks it, putting the VKS Service into "Error" state. This is **transient** and self-resolves in ~30 minutes when kapp retries.

**In simple terms:** Two parts of the system are starting up at the same time and step on each other. Part A needs something from Part B, but Part B isn't ready yet. After ~30 minutes, Part B finishes and Part A's retry succeeds.

### 2. Stale Webhook Cache (VKS 3.4.x Release Notes)

The `vmware-system-tkg-webhook` caches the **old** ClusterClass variable schema from before the upgrade. It rejects `vmClass`, `storageClass`, and `kubernetes` as "not defined" because its cache hasn't refreshed yet. **This is the direct cause of the admission webhook error.**

**In simple terms:** The bouncer (webhook) has a printed guest list from yesterday. Your name is on today's list, but the bouncer hasn't picked up the new copy yet. Restarting the webhook pod forces it to reload the current list.

### 3. Certificate Staleness on runtime-extension-controller-manager (KB 423284 / KB 424003)

A new TLS certificate is generated during the upgrade, but the running `runtime-extension-controller-manager` pod doesn't reload it. The CAPI controller-manager can't reach the runtime-extension webhook (`x509: certificate signed by unknown authority`), so the ClusterClass `VariablesReconciled` condition stays `False`. This blocks **all** cluster lifecycle operations. This issue recurs every ~60 days until a permanent fix ships.

**In simple terms:** During the upgrade, a new security certificate (like an ID badge) was issued. But the controller that needs to present this badge is still carrying the old, expired one. Other services don't trust the old badge, so they refuse to talk to it. Deleting the old badge and restarting the controller forces it to pick up the new one.

### Chain of Events

```
Upload VKS 3.4.0 → Manage Service → Finish
  │
  ▼
kapp-controller reconciles VKS packages
  │
  ├─ RuntimeSDK feature flag race → Service status = "Error" (~30 min)
  │
  ▼
Service status eventually → "Configured"
  │
  BUT controllers may still have stale certs/cache
  │
  ▼
ClusterClass builtin-generic-v3.4.0 deployed to vmware-system-vks-public
  │
  ├─ VariablesReconciled may still = False (Issue #3 - stale TLS cert)
  │
  ▼
Student creates vks-01 via VCFA
  │
  ▼
CAPI webhook rejects: "variable is not defined" (Issue #2 - stale cache)
  │
  ▼
Controllers eventually restart / cache refreshes (~30-60 min total)
  │
  ▼
Cluster creation succeeds
```

## Root Cause Summary

- The CAPI webhook validates cluster specs against the **ClusterClass schema** — this is the "form template" that says what variables are allowed
- VKS 3.4.0 introduced `builtin-generic-v3.4.0` with a **different variable schema** than v3.3.0 and earlier
- Starting with VKS 3.4, ClusterClasses are stored in `vmware-system-vks-public` namespace (no longer replicated to all namespaces)
- The webhook rejects requests when variables in the cluster spec don't match the ClusterClass variable definitions
- Deprecated variables (e.g., `defaultStorageClass`, `nodePoolVolumes`, `trust`) are no longer valid in v3.4.0

---

## Prerequisites / Access

### What You Need To Know

The Supervisor is the management layer that runs VKS. It has its own Kubernetes API and its own set of VMs (called "Control Plane VMs" or "CP VMs"). There are two ways to interact with it:

1. **kubectl from your workstation** — you connect to the Supervisor API remotely. This works for reading data (diagnostics), but the Supervisor's admission webhook blocks certain write operations like restarting deployments.
2. **SSH into a CP VM** — you log directly into one of the three Supervisor Control Plane VMs. From there, `kubectl` has full admin privileges with no webhook restrictions.

**Why can't kubectl just restart deployments remotely?** The Supervisor has a protective admission webhook (`admission.vmware.com`) that prevents external contexts from modifying system deployments. It blocks the `master taint toleration` needed for rollout restarts. This is a security feature — only processes running directly on the CP VMs are trusted to restart system controllers.

**Context needed:** Supervisor context with access to `svc-tkg-domain-c*` namespace. In this lab, the admin Supervisor context (`vcf context use supervisor`) has sufficient RBAC for **diagnostics**. For remediation (controller restarts), SSH into a Supervisor CP VM is required.

### Access Method 1: kubectl from Supervisor Context (try first)

This gives you read access for diagnostics. The script uses this for all the checks in Steps 1-11.

```bash
vcf context use supervisor

# Test access - if this returns results, you have diagnostic access
kubectl get deployment -n svc-tkg-domain-c10 vmware-system-tkg-webhook
```

### Access Method 2: SSH into a Supervisor CP VM (fallback for fixes)

> **Automated:** `./vks-capi-webhook-troubleshoot.sh --fix` handles this entire flow automatically — when kubectl is blocked, it retrieves the password from vCenter and SSHes into a CP VM to run the fix. You don't need to do this manually.

> **Important:** The Supervisor API VIP (10.1.0.6) does NOT accept SSH — only port 443. SSH must target the individual CP VM management IPs.

**How the SSH fallback works (what the script does for you):**

1. The script SSHes into vCenter (`vc-wld01-a.site-a.vcf.lab`) using the vCenter root password
2. It runs `/usr/lib/vmware-wcp/decryptK8Pwd.py` — a VMware utility that decrypts the auto-generated root password for the Supervisor CP VMs (this password is different from the vCenter password and is unique to each lab instance)
3. It parses the `PWD:` line from the output to get the CP VM password
4. It tries SSHing to each CP VM IP (10.1.1.85, 10.1.1.86, 10.1.1.87, 10.1.1.88) until one responds
5. It runs the fix commands on the CP VM, where kubectl has full cluster-admin privileges

**If you need to do this manually:**

```bash
# Step 1: Get the CP VM root password from vCenter appliance
ssh root@vc-wld01-a.site-a.vcf.lab
#  Password: VMware123!VMware123!
#  If you get the VCSA shell prompt, type: shell

/usr/lib/vmware-wcp/decryptK8Pwd.py
#  Output shows PWD: <generated-password>

# Step 2: SSH into a CP VM (NOT the API VIP)
ssh root@10.1.1.85
#  Password: the PWD value from decryptK8Pwd.py
```

> **Note:** The Supervisor CP VM password is auto-generated per lab instance — it is NOT `VMware123!VMware123!`. You must retrieve it from vCenter using `decryptK8Pwd.py` each time.

Once on the CP VM, kubectl is pre-configured with full cluster-admin privileges — no context switching needed.

> **Note:** The namespace `svc-tkg-domain-c10` is specific to this lab environment. In other environments, find yours with `kubectl get ns | grep svc-tkg`.

---

## Automated Script

A single script handles all diagnostics and remediation: **`vks-capi-webhook-troubleshoot.sh`**

```bash
# Diagnose only (safe, read-only — makes no changes)
./vks-capi-webhook-troubleshoot.sh

# Diagnose + restart controllers (auto-falls back to SSH if kubectl is blocked)
./vks-capi-webhook-troubleshoot.sh --fix

# Diagnose + restart + cert regeneration if VariablesReconciled is still False
./vks-capi-webhook-troubleshoot.sh --fix-cert

# Just retrieve and display the CP VM password (for manual SSH access)
./vks-capi-webhook-troubleshoot.sh --get-password
```

### What Each Mode Does

**Diagnose only (no flags):** Runs 12 read-only checks — connectivity, kubectl context, ClusterClass availability, TKR readiness, existing clusters, controller health, webhook config, VM/storage classes, package reconciliation, VariablesReconciled condition, x509 cert errors, and cert expiry. Reports PASS/FAIL/WARN for each. Makes no changes.

**--fix:** Runs all diagnostics, then restarts three key controllers:
- `vmware-system-tkg-webhook` — clears the stale ClusterClass variable cache
- `runtime-extension-controller-manager` — picks up the new TLS certificate
- `capi-controller-manager` — re-syncs with the runtime-extension webhook

If `kubectl rollout restart` is blocked by the admission webhook (the normal case from an external context), the script automatically SSHes into a Supervisor CP VM to run the restarts with full privileges.

**--fix-cert:** Same as `--fix`, plus: after restarting, it checks if `VariablesReconciled` is still `False`. If so, it deletes the stale certificate secret (`runtime-extension-webhook-service-cert`) to force the system to generate a fresh one, then restarts the controllers again.

**--get-password:** SSHes into vCenter and runs `decryptK8Pwd.py` to display the CP VM root password. Useful if you want to SSH in manually.

### How the SSH Fallback Works

When `--fix` or `--fix-cert` is used, the script:
1. First tries `kubectl rollout restart` from your current context
2. If it gets the `admission webhook "admission.vmware.com" denied` error (expected), it switches to SSH mode
3. SSHes into vCenter to retrieve the CP VM password via `decryptK8Pwd.py`
4. SSHes into a CP VM and runs the restarts there
5. Runs post-fix verification via SSH

All of this is automatic — you just run `./vks-capi-webhook-troubleshoot.sh --fix` and wait.

See `README.md` for full option reference.

---

## Troubleshooting Commands

These are the manual equivalents of what the script does. Use them if you prefer to investigate step-by-step, or if the script isn't available.

### 1. Verify Supervisor Connectivity

**What this checks:** Can your workstation reach the Supervisor API and vCenter? If these fail, you have a network problem unrelated to the webhook issue.

```bash
# Test Supervisor API connectivity
ping -c 3 <SUPERVISOR_IP>
curl -sk https://<SUPERVISOR_IP>:6443/api

# Test vCenter connectivity
ping -c 3 vc-wld01-a.site-a.vcf.lab
curl -sk https://vc-wld01-a.site-a.vcf.lab
```

### 2. Check kubectl Context

**What this checks:** Is kubectl pointed at the right Supervisor? You might have multiple contexts configured. The active context determines which cluster your commands run against.

```bash
# View current config and contexts
kubectl config view
kubectl config get-contexts

# Switch to Supervisor context
kubectl config use-context supervisor
```

### 3. Check ClusterClass Availability

**What this checks:** Has the new ClusterClass template (`builtin-generic-v3.4.0`) been deployed? If it's missing, VKS 3.4.0 installation may not have completed yet.

This is the **key diagnostic step**. Verify which ClusterClass versions exist and where:

```bash
# List ALL ClusterClasses across all namespaces
kubectl get clusterclass -A

# Check if v3.4.0 exists in the central namespace (VKS 3.4+ location)
kubectl get clusterclass builtin-generic-v3.4.0 -n vmware-system-vks-public

# Check if v3.4.0 exists in your workload namespace (will be NotFound for VKS 3.4+)
kubectl get clusterclass builtin-generic-v3.4.0 -n <YOUR-NAMESPACE>

# Describe the ClusterClass for detailed variable schema
kubectl describe clusterclass builtin-generic-v3.4.0 -n vmware-system-vks-public

# Get full YAML of ClusterClass
kubectl get clusterclass builtin-generic-v3.4.0 -n vmware-system-vks-public -o yaml
```

**Expected result for VKS 3.4+:**
- `builtin-generic-v3.4.0` exists ONLY in `vmware-system-vks-public`
- Workload namespaces will have v3.1.0, v3.2.0, v3.3.0 (replicated), but NOT v3.4.0

### 4. Check Available Kubernetes Releases (TKR/VKR)

**What this checks:** Which Kubernetes versions are ready to use? Each TKR (TanzuKubernetesRelease) represents a K8s version that has been packaged and validated for this Supervisor. Only `READY=True` versions can be used for new clusters.

```bash
# List TKRs (legacy command, still works)
kubectl get tanzukubernetesreleases

# Filter to only READY releases
kubectl get tanzukubernetesreleases | grep True

# List Kubernetes Releases (new command)
kubectl get kubernetesreleases -A

# Check specific TKR details
kubectl describe tanzukubernetesrelease <TKR-NAME>
```

### 5. Check Existing Clusters

**What this checks:** Are your existing clusters healthy? The `Phase` column tells you: `Provisioned` = healthy, `Provisioning` = still being created, `Failed` = something went wrong.

```bash
# List all CAPI clusters and their ClusterClass
kubectl get clusters -A

# Describe a specific cluster to see its topology and variables
kubectl describe cluster <CLUSTER-NAME> -n <NAMESPACE>

# Get cluster YAML to inspect variables and annotations
kubectl get cluster <CLUSTER-NAME> -n <NAMESPACE> -o yaml

# Check for skip-auto-cc-rebase annotation
kubectl get cluster <CLUSTER-NAME> -n <NAMESPACE> -o jsonpath='{.metadata.annotations.kubernetes\.vmware\.com/skip-auto-cc-rebase}'
```

### 6. Check CAPI Controller Status

**What this checks:** Are all the controller deployments running with the expected number of replicas? If a deployment shows `1/2 READY`, one of its pods has crashed or is restarting.

```bash
# Check all deployments in the VKS service namespace
kubectl get deployments -n svc-tkg-domain-c10

# Check CAPI infrastructure provider pods
kubectl get pods -n vmware-system-capw
kubectl get pods -n vmware-system-capv

# Check CAPI controller logs (look for errors)
kubectl logs -n vmware-system-capw -c manager $(kubectl get pods -n vmware-system-capw -o jsonpath='{.items[0].metadata.name}') --tail=50
```

### 7. Check Webhook Configuration

**What this checks:** Are the CAPI admission webhooks registered? These are the gatekeepers that validate cluster creation requests. If they're misconfigured or missing, cluster operations may fail or be unvalidated.

> Note: These require cluster-scope RBAC which namespace-scoped Supervisor contexts don't have. You'll get "Forbidden" — that's expected. SSH into a CP VM to see these.

```bash
# List mutating webhooks (look for the CAPI ones)
kubectl get mutatingwebhookconfigurations | grep capi

# List validating webhooks
kubectl get validatingwebhookconfigurations | grep capi

# Describe the specific webhook causing the error
kubectl describe mutatingwebhookconfiguration capi-mutating-webhook-configuration
```

### 8. Check VM Classes and Storage Classes

**What this checks:** Are the VM sizes and storage policies available that your cluster manifest references? If `vmClass: best-effort-medium` is in your YAML but that class doesn't exist in your namespace, creation will fail (though with a different error than the webhook issue).

```bash
# List VM classes bound to namespace
kubectl get virtualmachineclasses -n <NAMESPACE>

# List storage classes
kubectl get storageclasses

# List content sources
kubectl get contentsources
kubectl get contentsourcebindings -A

# List VM images available
kubectl get virtualmachineimages -A
```

### 9. Check VKS Package Installation Status

**What this checks:** Has the VKS 3.4.0 package fully reconciled? If it shows anything other than "Reconcile succeeded", the installation is still in progress or has failed.

```bash
# Check package installs
kubectl get packageinstalls -A | grep vks

# Check package repositories
kubectl get packagerepositories -A

# Check kapp apps
kubectl get apps -A | grep vks
```

---

## Remediation

> **RBAC Limitation:** The `kubectl rollout restart` commands below will fail from the external Supervisor context with `admission webhook "admission.vmware.com" denied the request: Cannot add toleration for master taint`. You must run these commands from a **Supervisor CP VM via SSH** (see Access Method 2 above), where kubectl has full cluster-admin privileges. The easiest way is to run **`./vks-capi-webhook-troubleshoot.sh --fix`**, which automatically falls back to SSH with password retrieval when kubectl is blocked.

### Fix Option A: Force-Restart the Controllers (immediate)

**What this does:** Restarting these three deployments forces Kubernetes to create new pods. The new pods start fresh — they load the current ClusterClass schema (clearing the stale cache) and pick up the new TLS certificate. This is like rebooting a computer to clear a stale state.

```bash
# Confirm the VKS service namespace
kubectl get ns | grep svc-tkg

# Restart the webhook (clears stale variable cache)
kubectl rollout restart deployment vmware-system-tkg-webhook -n svc-tkg-domain-c10

# Restart the runtime-extension controller (picks up new TLS cert)
kubectl rollout restart deployment runtime-extension-controller-manager -n svc-tkg-domain-c10

# Restart the CAPI controller (re-syncs with runtime-extension)
kubectl rollout restart deployment capi-controller-manager -n svc-tkg-domain-c10
```

Cluster creation should work within a few minutes after the pods restart.

**If restart alone doesn't fix it — check ClusterClass conditions:**

The controllers may restart successfully but the underlying certificate or reconciliation issue may persist. The key indicator is the `VariablesReconciled` condition on the ClusterClass:

- **VariablesReconciled = True** — the system is healthy, cluster creation should work
- **VariablesReconciled = False** — the TLS certificate is still stale, you need to delete it (see below)

```bash
# Check ClusterClass exists and VariablesReconciled = True
kubectl get clusterclass -A | grep builtin-generic

kubectl get cc -n svc-tkg-domain-c10 builtin-generic-v3.4.0 -o jsonpath='{.status.conditions}' | jq
#  VariablesReconciled must be True. If False, the webhook cert is still stale.

# Check runtime-extension-controller-manager logs for cert errors
kubectl logs -n svc-tkg-domain-c10 -l app=runtime-extension-controller-manager --tail=50
#  Look for "x509: certificate signed by unknown authority"

# Check webhook certificate validity
kubectl get secret runtime-extension-webhook-service-cert -n svc-tkg-domain-c10 \
  -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -dates -serial
#  Verify Not After is in the future
```

**If VariablesReconciled is still False after restart, delete the stale cert secret to force regeneration (KB 424003):**

```bash
# Delete the old certificate — the system will automatically generate a new one
kubectl delete secret runtime-extension-webhook-service-cert -n svc-tkg-domain-c10

# Restart the controllers so they pick up the new cert
kubectl rollout restart deployment runtime-extension-controller-manager -n svc-tkg-domain-c10
kubectl rollout restart deployment capi-controller-manager -n svc-tkg-domain-c10
```

### Fix Option B: Wait It Out (~30-60 min)

The error is transient. kapp-controller will eventually cycle the pods and refresh the cache. This happens automatically — you don't need to do anything. Monitor progress from the CP VM:

```bash
# Check VKS package reconciliation status
kubectl get packageinstall -n vmware-system-supervisor-services | grep svc-tkg
#  Wait for "Reconcile succeeded"

# Check ClusterClass readiness
kubectl describe clusterclass builtin-generic-v3.4.0 -n vmware-system-vks-public
#  Look for: VariablesReconciled = True

# Check all CAPI deployments are healthy (2/2 replicas)
kubectl get deployments -n svc-tkg-domain-c10
```

### How to Avoid It Entirely

As the instructor, install VKS 3.4.0 **at least 60 minutes** before students attempt to create clusters. The RUNBOOK Step 2 does this, but the timing matters — if the lab environment was freshly provisioned, allow the full reconciliation window before proceeding to Step 7 (Create vks-01 Cluster).

---

## Resolution Steps (Variable/ClusterClass Mismatch)

This section covers a different scenario: your cluster manifest uses the wrong variable names for the ClusterClass version, which causes the same "variable is not defined" error even after the controllers are healthy.

### Scenario A: Creating a NEW Cluster with VKS 3.4.0

Use the `builtin-generic-v3.4.0` ClusterClass with the **correct variable schema**. Example manifest:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
  namespace: <namespace>
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/16
    services:
      cidrBlocks:
      - 10.96.0.0/12
  topology:
    class: builtin-generic-v3.4.0
    version: v1.33.6+vmware.1-fips
    controlPlane:
      replicas: 1
    workers:
      machineDeployments:
      - class: node-pool
        name: np-1
        replicas: 3
        variables:
          overrides:
          - name: vmClass
            value: guaranteed-medium
    variables:
    - name: vmClass
      value: guaranteed-medium
    - name: storageClass
      value: <your-storage-class>
```

**Key change:** Variables like `vmClass` and `storageClass` must be explicitly defined. Do NOT use deprecated variables like `defaultStorageClass`.

### Scenario B: Upgrading an EXISTING Cluster to v3.4.0

**What is "rebasing"?** When you change a cluster's ClusterClass from an old version (v3.3.0) to a new one (v3.4.0), that's called a "rebase." VKS can do this automatically when you update the K8s version, or you can do it manually.

**Option 1 — Update K8s version (auto-rebases ClusterClass):**

```bash
kubectl edit cluster <cluster-name> -n <namespace>
```

1. Remove the annotation: `kubernetes.vmware.com/skip-auto-cc-rebase`
2. Update `spec.topology.version` to a version supported by VKS 3.4 (e.g., `v1.33.6+vmware.1-fips`)
3. Save — VKS will automatically rebase to `builtin-generic-v3.4.0`

**Option 2 — Update ClusterClass only (keep K8s version):**

```bash
kubectl edit cluster <cluster-name> -n <namespace>
```

1. Remove the annotation: `kubernetes.vmware.com/skip-auto-cc-rebase`
2. Update `spec.topology.class` to `builtin-generic-v3.4.0`
3. Save

**Option 3 — For clusters on v3.2.0+ (no skip annotation):**

```bash
kubectl edit cluster <cluster-name> -n <namespace>
```

Simply update `spec.topology.version` to the target version and save.

### Scenario C: Variable Schema Mismatch

If your YAML uses deprecated variables from older ClusterClass versions, you need to convert them to the new names:

| Deprecated Variable (v3.1.x) | New Variable (v3.2.x+) |
|---|---|
| `defaultStorageClass` | `vsphereOptions.persistentVolumes.defaultStorageClass` |
| `ntp` | `osConfiguration.ntp.servers` |
| `storageClasses` | `vsphereOptions.persistentVolumes.availableStorageClasses` |
| `nodePoolVolumes` | Removed in v3.4 — use per-node-pool storage config |
| `trust` | Removed in v3.4 — use certificate management |

For automated conversion, use the `vks-variable-convert` tool referenced in Broadcom docs.

---

## Verification After Fix

**What to look for:** After applying the fix, these commands tell you if the system is healthy and cluster creation should work.

```bash
# Is the cluster being created? Phase should be "Provisioning" then "Provisioned"
kubectl get clusters -A
kubectl get cluster <CLUSTER-NAME> -n <NAMESPACE> -o jsonpath='{.status.phase}'

# Are there any error conditions on the cluster?
kubectl get cluster <CLUSTER-NAME> -n <NAMESPACE> -o jsonpath='{.status.conditions}' | jq .

# Are VMs (machines) being created for the cluster?
kubectl get machines -n <NAMESPACE>

# Is the control plane initializing? Look for INITIALIZED=true
kubectl get kubeadmcontrolplanes -n <NAMESPACE>

# Are worker nodes scaling up? Look for READY count matching REPLICAS
kubectl get machinedeployments -n <NAMESPACE>

# Are there any remaining webhook errors in recent events?
kubectl get events -n <NAMESPACE> --sort-by='.lastTimestamp' | tail -20
```

---

## Lab Environment Reference

| Component | Address |
|---|---|
| vCenter (WLD) | https://vc-wld01-a.site-a.vcf.lab (10.1.1.11) |
| Supervisor API VIP | 10.1.0.6 (port 443 only, no SSH) |
| VCFA | auto-a.site-a.vcf.lab |
| Supervisor Context | `supervisor` |
| Supervisor CP VMs | 10.1.1.85, 10.1.1.86, 10.1.1.87, 10.1.1.88 |
| VKS Service Namespace | `svc-tkg-domain-c10` |
| vCenter SSH password | `VMware123!VMware123!` |
| CP VM SSH password | `rAV&C[D=z|9>?iNC` (embedded in script; if it changes, update script line 78 or use `--cp-password`) |

**Current ClusterClass versions on this Supervisor:**
- `builtin-generic-v3.1.0` (all namespaces, replicated)
- `builtin-generic-v3.2.0` (all namespaces, replicated)
- `builtin-generic-v3.3.0` (all namespaces, replicated)
- `builtin-generic-v3.4.0` (vmware-system-vks-public only)
- `tanzukubernetescluster` (legacy, all namespaces)

**Available Ready TKRs (K8s versions):**
- v1.29.4, v1.29.15
- v1.30.1, v1.30.8, v1.30.11, v1.30.14
- v1.31.4, v1.31.7, v1.31.11, v1.31.14
- v1.32.0, v1.32.3, v1.32.7, v1.32.10
- v1.33.1, v1.33.3, v1.33.6

**Existing Clusters:**
- `kubernetes-cluster-ngco` (dev-cd5rq) - v3.4.0 / v1.33.6 - Provisioned
- `prod-vks-02` (production-c5b8n) - v3.3.0 / v1.32.0 - Provisioned

---

## Troubleshooting Run Results (2026-02-17)

Full runbook executed against the live environment after VKS 3.4.0 installation.

### Connectivity

| Check | Result |
|---|---|
| Supervisor API (10.1.0.6) | Reachable, 0% packet loss |
| vCenter (vc-wld01-a.site-a.vcf.lab) | Reachable, HTTPS responding |
| kubectl context | `supervisor` active, `svc-tkg-domain-c10` accessible |

### ClusterClass Availability

| Namespace | v3.1.0 | v3.2.0 | v3.3.0 | v3.4.0 |
|---|---|---|---|---|
| vmware-system-vks-public | Present | Present | Present | **Present** |
| dev-cd5rq | Present | Present | Present | Not replicated (expected) |
| production-c5b8n | Present | Present | Present | Not replicated (expected) |

### TKR Readiness

- 17 releases Ready/Compatible (v1.29 through v1.33.6)
- All showing `READY=True`, `COMPATIBLE=True`

### CAPI Controller Status

All 16 deployments in `svc-tkg-domain-c10` healthy:

| Deployment | Ready |
|---|---|
| capi-controller-manager | 2/2 |
| capi-kubeadm-bootstrap-controller-manager | 2/2 |
| capi-kubeadm-control-plane-controller-manager | 2/2 |
| capv-controller-manager | 2/2 |
| runtime-extension-controller-manager | 1/1 |
| vmware-system-tkg-controller-manager | 2/2 |
| vmware-system-tkg-webhook | 2/2 |
| tanzu-addons-controller-manager | 1/1 |
| tanzu-auth-controller-manager | 1/1 |
| tkgs-plugin-server | 2/2 |
| tkr-conversion-webhook-manager | 1/1 |
| tkr-resolver-cluster-webhook-manager | 1/1 |
| tkr-status-controller-manager | 1/1 |
| machine-agent-server | 1/1 |
| upgrade-compatibility-service | 1/1 |
| vmware-system-tkg-state-metrics | 2/2 |

### VKS Package Reconciliation

```
svc-tkg.vsphere.vmware.com    tkg.vsphere.vmware.com    3.4.1+v1.33    Reconcile succeeded
```

### Key Diagnostic Checks

| Check | Result | Status |
|---|---|---|
| `VariablesReconciled` | **True** (since 2026-02-17T05:54:52Z) | HEALTHY |
| `RefVersionsUpToDate` | **True** (since 2026-02-17T05:43:52Z) | HEALTHY |
| runtime-extension logs | No x509 errors found | HEALTHY |
| Webhook cert `notAfter` | **May 17, 2026** (~89 days remaining) | HEALTHY |
| Webhook cert `notBefore` | Feb 16, 2026 | - |
| Webhook cert serial | 68FA3463C111F122748C9E4CA4DEAD38 | - |

### Cluster Status

| Cluster | Namespace | ClusterClass | Phase | K8s Version |
|---|---|---|---|---|
| kubernetes-cluster-ngco | dev-cd5rq | builtin-generic-v3.4.0 | **Provisioned** | v1.33.6+vmware.1-fips |
| prod-vks-02 | production-c5b8n | builtin-generic-v3.3.0 | **Provisioned** | v1.32.0+vmware.6-fips |

### Verdict

**All systems healthy.** The VKS 3.4.0 reconciliation completed successfully. No stale caches, no certificate issues, `VariablesReconciled=True`, all controllers running with full replicas. Cluster creation via VCFA is working.

The webhook certificate expires **May 17, 2026** — per KB 424003, monitor around that date for the ~60 day cert rotation recurrence.

The issue could not be reproduced because the ~30-60 minute reconciliation window had already passed by the time troubleshooting began.

---

## Broadcom KB References

**Directly related to this issue:**
- [KB 392756 - RuntimeSDK feature flag race (~30 min transient)](https://knowledge.broadcom.com/external/article/392756)
- [KB 414721 - Admission webhook denied after upgrading ClusterClass to v3.4.0](https://knowledge.broadcom.com/external/article/414721)
- [KB 423284 - ClusterClass not reconciled (stale cert)](https://knowledge.broadcom.com/external/article/423284)
- [KB 424003 - VariablesReconciled must be True (cert rotation bug, recurs every 60 days)](https://knowledge.broadcom.com/external/article/424003)

**Variable schema and ClusterClass:**
- [KB 410037 - Workload cluster creation fails on VKS 3.4 with variable validation error](https://knowledge.broadcom.com/external/article/410037)
- [KB 411452 - Cluster update from VKR 1.32.3 to 1.33.1 fails with webhook validation errors](https://knowledge.broadcom.com/external/article/411452/cluster-update-from-vkr-1323-to-1331-fai.html)
- [KB 404143 - Variable conversion for VKS/TKGS clusters](https://knowledge.broadcom.com/external/article/404143/variable-conversion-for-vsphere-kubernet.html)
- [Using builtin-generic-v3.4.0 ClusterClass](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vsphere-supervisor-services-and-standalone-components/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/provisioning-tkg-service-clusters/using-the-cluster-v1beta1-api/using-the-versioned-clusterclass/usingbuiltingenericv340.html)

**General troubleshooting:**
- [KB 388260 - Troubleshooting Supervisor workload cluster VIP connection issues](https://knowledge.broadcom.com/external/article/388260/troubleshooting-vsphere-supervisor-workl.html)
- [Troubleshoot VKS Cluster Provisioning Errors](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vsphere-supervisor-services-and-standalone-components/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/troubleshooting-tkg-service-clusters/troubleshoot-tkg-cluster-provisioning-errors.html)
- [Pull Logs to Troubleshoot VKS Clusters](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vsphere-supervisor-services-and-standalone-components/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/troubleshooting-tkg-service-clusters/pull-logs-to-troubleshoot-tkg-clusters.html)
- [Troubleshoot VKS Cluster Networking Errors](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vsphere-supervisor-services-and-standalone-components/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads/troubleshooting-tkg-service-clusters/troubleshoot-tkg-cluster-networking-errors.html)
