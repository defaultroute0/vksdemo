# VKS CAPI Webhook Troubleshooting Script

Automated diagnostic and remediation script for the **"variable is not defined"** CAPI admission webhook error that occurs after upgrading VKS (vSphere Kubernetes Service) on a vSphere Supervisor.

## Problem

After installing VKS 3.4.0 on the Supervisor, cluster creation fails for ~30-60 minutes with:

```
admission webhook "capi.mutating.tanzukubernetescluster.run.tanzu.vmware.com" denied the request:
  variable is not defined
```

Three overlapping causes:
1. **RuntimeSDK feature flag race condition** (KB 392756)
2. **Stale webhook cache** (VKS 3.4.x release notes)
3. **Stale TLS cert** on runtime-extension-controller-manager (KB 423284 / KB 424003)

## Quick Start

```bash
# Make executable (one time)
chmod +x vks-capi-webhook-troubleshoot.sh

# Diagnose only (safe, read-only)
./vks-capi-webhook-troubleshoot.sh

# Diagnose + restart controllers (fixes the issue)
./vks-capi-webhook-troubleshoot.sh --fix

# Diagnose + restart + regenerate stale cert (if VariablesReconciled=False)
./vks-capi-webhook-troubleshoot.sh --fix-cert

# Retrieve Supervisor CP VM password from vCenter (for SSH access)
./vks-capi-webhook-troubleshoot.sh --get-password
```

## What It Checks

| Step | Check | What It Verifies |
|------|-------|------------------|
| 0 | CP VM Password (optional) | Retrieves root password from vCenter via `decryptK8Pwd.py` |
| 1 | Connectivity | Ping + HTTPS to Supervisor API VIP and vCenter |
| 2 | kubectl Context | Active context is a Supervisor context |
| 3 | ClusterClass Availability | `builtin-generic-v3.4.0` exists in `vmware-system-vks-public` |
| 4 | TKR Readiness | TanzuKubernetesReleases in READY state |
| 5 | Existing Clusters | All clusters Provisioned, shows ClusterClass + version |
| 6 | CAPI Controller Status | All 16 deployments in svc-tkg namespace are healthy |
| 7 | Webhook Configuration | Mutating/validating webhook configs (requires cluster-scope RBAC) |
| 8 | VM/Storage Classes | Available VM classes and storage classes |
| 9 | VKS Package Status | Package reconciliation succeeded |
| 10 | Key Diagnostics | `VariablesReconciled` condition, x509 cert errors, cert expiry |
| 11 | Cluster Health | Per-cluster machines, control plane, events |

## Modes

### Diagnose Only (default)

Runs all checks, reports PASS/FAIL/WARN for each, and provides a summary. No changes are made.

### --fix (Restart Controllers)

After running diagnostics, restarts the three controllers that cause the webhook error:
- `vmware-system-tkg-webhook` (stale ClusterClass cache)
- `runtime-extension-controller-manager` (stale TLS cert)
- `capi-controller-manager` (re-sync with runtime-extension)

### --fix-cert (Restart + Certificate Regeneration)

Same as `--fix`, plus: if `VariablesReconciled` is still `False` after restarting, deletes the stale `runtime-extension-webhook-service-cert` secret to force regeneration (per KB 424003).

### --get-password (Retrieve CP VM Password)

SSHes into vCenter and runs `/usr/lib/vmware-wcp/decryptK8Pwd.py` to retrieve the auto-generated Supervisor Control Plane VM root password. Requires `sshpass` for non-interactive operation.

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--fix` | Restart controllers after diagnosis | Off |
| `--fix-cert` | Restart + delete stale cert if needed | Off |
| `--get-password` | Retrieve CP VM password from vCenter | Off |
| `--namespace <ns>` | Override VKS service namespace | Auto-detected (`svc-tkg-domain-*`) |
| `--supervisor <ip>` | Supervisor API VIP | `10.1.0.6` |
| `--vcenter <fqdn>` | vCenter FQDN | `vc-wld01-a.site-a.vcf.lab` |
| `--vc-user <user>` | vCenter SSH user | `root` |
| `--vc-password <pw>` | vCenter SSH password | `VMware123!VMware123!` |
| `--cc-version <ver>` | ClusterClass version to check | `builtin-generic-v3.4.0` |

## Prerequisites

- `kubectl` configured with a Supervisor context
- RBAC access to the `svc-tkg-domain-c*` namespace
- For `--fix`/`--fix-cert`: RBAC to restart deployments (may require CP VM SSH)
- For `--get-password`: SSH access to vCenter, `sshpass` recommended
- `jq` and `openssl` for certificate inspection (optional but recommended)

## RBAC Note

If the `--fix` and `--fix-cert` modes detect that `kubectl rollout restart` is blocked by the admission webhook:

```
admission webhook "admission.vmware.com" denied the request:
Cannot add toleration for master taint
```

The script automatically falls back to SSH: it retrieves the CP VM root password from vCenter via `decryptK8Pwd.py`, connects to a Supervisor CP VM, and runs the fix commands with full cluster-admin privileges. No manual intervention needed.

## Related KBs

- [KB 392756](https://knowledge.broadcom.com/external/article/392756) - RuntimeSDK feature flag race
- [KB 414721](https://knowledge.broadcom.com/external/article/414721) - Admission webhook denied after ClusterClass upgrade
- [KB 423284](https://knowledge.broadcom.com/external/article/423284) - ClusterClass not reconciled (stale cert)
- [KB 424003](https://knowledge.broadcom.com/external/article/424003) - VariablesReconciled must be True (cert rotation bug)

## Files

| File | Description |
|------|-------------|
| `vks-capi-webhook-troubleshoot.sh` | All-in-one diagnostic/remediation script with automatic SSH fallback |
| `VKS-CAPI-Webhook-Troubleshooting.md` | Full troubleshooting guide with background and manual steps |
