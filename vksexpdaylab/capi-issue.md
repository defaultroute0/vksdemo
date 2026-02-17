# VKS CAPI Admission Webhook Troubleshooting Guide

**Environment:** VCF 9 / vSphere Supervisor
**Issue:** CAPI errors when creating or upgrading VKS clusters after VKS version upgrade
**Last Updated:** 2026-02-17

---

## TL;DR

After installing VKS 3.4.0 on the Supervisor, cluster creation fails for ~30-60 minutes with `"variable is not defined"` webhook errors. Three overlapping causes: RuntimeSDK feature flag race (KB 392756), stale webhook cache (VKS 3.4.x release notes), and stale TLS cert on runtime-extension-controller-manager (KB 423284 / KB 424003).

**Quick fix** (from Supervisor context or CP VM SSH):
```bash
kubectl rollout restart deployment vmware-system-tkg-webhook -n svc-tkg-domain-c10
kubectl rollout restart deployment runtime-extension-controller-manager -n svc-tkg-domain-c10
kubectl rollout restart deployment capi-controller-manager -n svc-tkg-domain-c10
```

**If still broken** - delete the stale cert to force regeneration:
```bash
kubectl delete secret runtime-extension-webhook-service-cert -n svc-tkg-domain-c10
kubectl rollout restart deployment runtime-extension-controller-manager -n svc-tkg-domain-c10
kubectl rollout restart deployment capi-controller-manager -n svc-tkg-domain-c10
```

**Or just wait ~60 minutes** - it self-resolves.

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

---

## What's Happening Under the Hood

Installing a new VKS version triggers a cascade of reconciliation on the Supervisor. Three things can go wrong, often overlapping:

### 1. RuntimeSDK Feature Flag Race Condition (KB 392756)

The kapp-controller reconciles VKS packages in parallel. The `runtime-extension` package tries to create `extensionconfig` resources **before** the RuntimeSDK feature flag is initialized. The CAPI admission webhook blocks it, putting the VKS Service into "Error" state. This is **transient** and self-resolves in ~30 minutes when kapp retries.

### 2. Stale Webhook Cache (VKS 3.4.x Release Notes)

The `vmware-system-tkg-webhook` caches the **old** ClusterClass variable schema from before the upgrade. It rejects `vmClass`, `storageClass`, and `kubernetes` as "not defined" because its cache hasn't refreshed yet. **This is the direct cause of the admission webhook error.**

### 3. Certificate Staleness on runtime-extension-controller-manager (KB 423284 / KB 424003)

A new TLS certificate is generated during the upgrade, but the running `runtime-extension-controller-manager` pod doesn't reload it. The CAPI controller-manager can't reach the runtime-extension webhook (`x509: certificate signed by unknown authority`), so the ClusterClass `VariablesReconciled` condition stays `False`. This blocks **all** cluster lifecycle operations. This issue recurs every ~60 days until a permanent fix ships.

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
Cluster creation succeeds ✓
```

## Root Cause Summary

- The CAPI webhook validates cluster specs against the **ClusterClass schema**
- VKS 3.4.0 introduced `builtin-generic-v3.4.0` with a **different variable schema** than v3.3.0 and earlier
- Starting with VKS 3.4, ClusterClasses are stored in `vmware-system-vks-public` namespace (no longer replicated to all namespaces)
- The webhook rejects requests when variables in the cluster spec don't match the ClusterClass variable definitions
- Deprecated variables (e.g., `defaultStorageClass`, `nodePoolVolumes`, `trust`) are no longer valid in v3.4.0

---

## Troubleshooting Commands

### 1. Verify Supervisor Connectivity

```bash
# Test Supervisor API connectivity
ping -c 3 <SUPERVISOR_IP>
curl -sk https://<SUPERVISOR_IP>:6443/api

# Test vCenter connectivity
ping -c 3 vc-wld01-a.site-a.vcf.lab
curl -sk https://vc-wld01-a.site-a.vcf.lab
```

### 2. Check kubectl Context

```bash
# View current config and contexts
kubectl config view
kubectl config get-contexts

# Switch to Supervisor context
kubectl config use-context supervisor
```

### 3. Check ClusterClass Availability

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

```bash
# Check CAPI controllers
kubectl get pods -n vmware-system-capw
kubectl get pods -n vmware-system-capv
kubectl get deployments -n vmware-system-capw

# Check CAPI controller logs
kubectl logs -n vmware-system-capw -c manager $(kubectl get pods -n vmware-system-capw -o jsonpath='{.items[0].metadata.name}') --tail=50

# Check the VKS system pods
kubectl get pods -n vmware-system-tkg
kubectl get pods -n vmware-system-vmop
```

### 7. Check Webhook Configuration

```bash
# List mutating webhooks (look for the CAPI ones)
kubectl get mutatingwebhookconfigurations | grep capi

# List validating webhooks
kubectl get validatingwebhookconfigurations | grep capi

# Describe the specific webhook causing the error
kubectl describe mutatingwebhookconfiguration capi-mutating-webhook-configuration
```

### 8. Check VM Classes and Storage Classes

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

```bash
# Check package installs
kubectl get packageinstalls -A | grep vks

# Check package repositories
kubectl get packagerepositories -A

# Check kapp apps
kubectl get apps -A | grep vks
```

---

## Prerequisites / Access

**Context needed:** Supervisor context with access to `svc-tkg-domain-c*` namespace. In this lab, the admin Supervisor context (`vcf context use supervisor`) has sufficient RBAC. If not, SSH into a Supervisor CP VM as a fallback.

### Access Method 1: kubectl from Supervisor Context (try first)

```bash
vcf context use supervisor

# Test access - if this returns results, you have access to run the fix commands below
kubectl get deployment -n svc-tkg-domain-c10 vmware-system-tkg-webhook
```

### Access Method 2: SSH into a Supervisor CP VM (fallback)

> **Important:** The API VIP (10.1.0.6) does NOT accept SSH - only port 443. SSH must target individual CP VM management IPs.

```bash
# Find CP VM IPs from vCenter: Hosts and Clusters → SupervisorControlPlaneVM → Summary → IP
# In this lab: 10.1.1.86, 10.1.1.87, 10.1.1.88

# Step 1: Get the CP VM root password from vCenter appliance
ssh root@vc-wld01-a.site-a.vcf.lab
#  Password: VMware123!VMware123!
#  If you get the VCSA shell prompt, type: shell

/usr/lib/vmware-wcp/decryptK8Pwd.py
#  Output shows PWD: <generated-password>

# Step 2: SSH into a CP VM (NOT the API VIP)
ssh root@10.1.1.86
#  Password: the PWD value from decryptK8Pwd.py
```

> **Note:** The Supervisor CP VM password is auto-generated per lab instance - it is NOT `VMware123!VMware123!`. You must retrieve it from vCenter using `decryptK8Pwd.py` each time.

Once on the CP VM, kubectl is pre-configured with full cluster-admin privileges.

> **Note:** The namespace `svc-tkg-domain-c10` is specific to this lab environment. In other environments, find yours with `kubectl get ns | grep svc-tkg`.

---

## Remediation

### Fix Option A: Force-Restart the Controllers (immediate)

```bash
# Confirm the VKS service namespace
kubectl get ns | grep svc-tkg

# Restart the webhook + CAPI controllers
kubectl rollout restart deployment vmware-system-tkg-webhook -n svc-tkg-domain-c10
kubectl rollout restart deployment runtime-extension-controller-manager -n svc-tkg-domain-c10
kubectl rollout restart deployment capi-controller-manager -n svc-tkg-domain-c10
```

Cluster creation should work within a few minutes after the pods restart.

**If restart alone doesn't fix it - check ClusterClass conditions:**

The controllers may restart successfully but the underlying certificate or reconciliation issue may persist. Verify with these diagnostic commands (from KB 424003 / KB 423284):

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
kubectl delete secret runtime-extension-webhook-service-cert -n svc-tkg-domain-c10
kubectl rollout restart deployment runtime-extension-controller-manager -n svc-tkg-domain-c10
kubectl rollout restart deployment capi-controller-manager -n svc-tkg-domain-c10
```

### Fix Option B: Wait It Out (~30-60 min)

The error is transient. kapp-controller will eventually cycle the pods and refresh the cache. Monitor progress from the CP VM:

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

As the instructor, install VKS 3.4.0 **at least 60 minutes** before students attempt to create clusters. The RUNBOOK Step 2 does this, but the timing matters - if the lab environment was freshly provisioned, allow the full reconciliation window before proceeding to Step 7 (Create vks-01 Cluster).

---

## Resolution Steps (Variable/ClusterClass Mismatch)

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

**Option 1 - Update K8s version (auto-rebases ClusterClass):**

```bash
kubectl edit cluster <cluster-name> -n <namespace>
```

1. Remove the annotation: `kubernetes.vmware.com/skip-auto-cc-rebase`
2. Update `spec.topology.version` to a version supported by VKS 3.4 (e.g., `v1.33.6+vmware.1-fips`)
3. Save - VKS will automatically rebase to `builtin-generic-v3.4.0`

**Option 2 - Update ClusterClass only (keep K8s version):**

```bash
kubectl edit cluster <cluster-name> -n <namespace>
```

1. Remove the annotation: `kubernetes.vmware.com/skip-auto-cc-rebase`
2. Update `spec.topology.class` to `builtin-generic-v3.4.0`
3. Save

**Option 3 - For clusters on v3.2.0+ (no skip annotation):**

```bash
kubectl edit cluster <cluster-name> -n <namespace>
```

Simply update `spec.topology.version` to the target version and save.

### Scenario C: Variable Schema Mismatch

If your YAML uses deprecated variables, convert them:

| Deprecated Variable (v3.1.x) | New Variable (v3.2.x+) |
|---|---|
| `defaultStorageClass` | `vsphereOptions.persistentVolumes.defaultStorageClass` |
| `ntp` | `osConfiguration.ntp.servers` |
| `storageClasses` | `vsphereOptions.persistentVolumes.availableStorageClasses` |
| `nodePoolVolumes` | Removed in v3.4 - use per-node-pool storage config |
| `trust` | Removed in v3.4 - use certificate management |

For automated conversion, use the `vks-variable-convert` tool referenced in Broadcom docs.

---

## Verification After Fix

```bash
# Verify cluster is provisioning/provisioned
kubectl get clusters -A
kubectl get cluster <CLUSTER-NAME> -n <NAMESPACE> -o jsonpath='{.status.phase}'

# Check cluster conditions
kubectl get cluster <CLUSTER-NAME> -n <NAMESPACE> -o jsonpath='{.status.conditions}' | jq .

# Check machines are being created
kubectl get machines -n <NAMESPACE>

# Check control plane status
kubectl get kubeadmcontrolplanes -n <NAMESPACE>

# Check machine deployments (worker nodes)
kubectl get machinedeployments -n <NAMESPACE>

# Check for any remaining webhook errors in events
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
| Supervisor CP VMs | 10.1.1.86, 10.1.1.87, 10.1.1.88 |
| VKS Service Namespace | `svc-tkg-domain-c10` |

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
- `tes-cluster02` (dev-cd5rq) - v3.4.0 / v1.33.6 - Provisioned
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
| tes-cluster02 | dev-cd5rq | builtin-generic-v3.4.0 | **Provisioned** | v1.33.6+vmware.1-fips |
| prod-vks-02 | production-c5b8n | builtin-generic-v3.3.0 | **Provisioned** | v1.32.0+vmware.6-fips |

### Verdict

**All systems healthy.** The VKS 3.4.0 reconciliation completed successfully. No stale caches, no certificate issues, `VariablesReconciled=True`, all controllers running with full replicas. Cluster creation via VCFA is working.

The webhook certificate expires **May 17, 2026** - per KB 424003, monitor around that date for the ~60 day cert rotation recurrence.

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
