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

Just run it — no arguments needed:

```bash
./vks-capi-webhook-troubleshoot.sh
```

This runs all 12 diagnostic checks, then automatically restarts the controllers via SSH to a Supervisor CP VM. All credentials and IPs for this lab are pre-configured.

## Usage

```
./vks-capi-webhook-troubleshoot.sh [options]

By default (no arguments), runs diagnostics AND restarts controllers.

Options:
  --diagnose-only  Run diagnostics only (no restarts, read-only)
  --fix-cert       Also delete stale cert if VariablesReconciled=False
  --get-password   Retrieve Supervisor CP VM root password from vCenter (via SSH)
  --cp-password    Override CP VM root password (default: pre-configured for this lab)
  --namespace      Override VKS service namespace (default: auto-detected)
  --supervisor     Supervisor API VIP (default: 10.1.0.6)
  --vcenter        vCenter FQDN (default: vc-wld01-a.site-a.vcf.lab)
  --vc-user        vCenter SSH user (default: root)
  --vc-password    vCenter SSH password (default: VMware123!VMware123!)
  --cc-version     ClusterClass version to check (default: builtin-generic-v3.4.0)
  --help           Show this help message
```

### Examples

```bash
# Default: diagnose + fix (this lab)
./vks-capi-webhook-troubleshoot.sh

# Diagnose only, no changes
./vks-capi-webhook-troubleshoot.sh --diagnose-only

# Fix + regenerate stale cert if needed
./vks-capi-webhook-troubleshoot.sh --fix-cert

# Use in a different lab environment
./vks-capi-webhook-troubleshoot.sh --supervisor 10.2.0.6 --vcenter vc-other.lab --cp-password 'otherpass'
```

## What It Does

1. Runs 12 diagnostic checks (connectivity, kubectl context, ClusterClass, TKRs, clusters, controllers, webhooks, VM/storage classes, packages, cert health)
2. Reports PASS/FAIL/WARN for each check
3. Restarts three key controllers via SSH to a CP VM:
   - `vmware-system-tkg-webhook` (clears stale ClusterClass cache)
   - `runtime-extension-controller-manager` (picks up new TLS cert)
   - `capi-controller-manager` (re-syncs with runtime-extension)
4. Verifies everything is healthy after the fix

If `kubectl rollout restart` is blocked by the Supervisor admission webhook (normal from an external context), the script automatically SSHes into a CP VM using the embedded password.

## Updating the CP VM Password

The CP VM root password is embedded in the script (line 78). If it changes:

- **Option 1:** Edit line 78 in `vks-capi-webhook-troubleshoot.sh`
- **Option 2:** Pass `--cp-password 'newpassword'` at runtime
- **Option 3:** Run `--get-password` to retrieve the current one from vCenter

## Prerequisites

- `kubectl` configured with a Supervisor context
- `sshpass` for CP VM SSH (auto-installed if missing)
- `jq` and `openssl` for certificate inspection (optional but recommended)

## Related KBs

- [KB 392756](https://knowledge.broadcom.com/external/article/392756) - RuntimeSDK feature flag race
- [KB 414721](https://knowledge.broadcom.com/external/article/414721) - Admission webhook denied after ClusterClass upgrade
- [KB 423284](https://knowledge.broadcom.com/external/article/423284) - ClusterClass not reconciled (stale cert)
- [KB 424003](https://knowledge.broadcom.com/external/article/424003) - VariablesReconciled must be True (cert rotation bug)

## Files

| File | Description |
|------|-------------|
| `vks-capi-webhook-troubleshoot.sh` | All-in-one diagnostic/remediation script |
| `VKS-CAPI-Webhook-Troubleshooting.md` | Full troubleshooting guide with background and manual steps |
| `README.md` | This file |
