# VKS Experience Day Lab — Quick Demo

This folder contains manifests and a demo script specifically for use against a **pre-configured Cloud and Kubernetes Experience Day lab environment**. The goal is to quickly demonstrate running both **Kubernetes workloads and VMs on the same VCF/VKS platform** — no lengthy setup required.

## What This Demonstrates

- **vSphere Pods** — deploying containerized apps directly into a Supervisor namespace
- **VM Service** — spinning up VMs alongside containers using `kind: VirtualMachine`
- **VKS Guest Clusters** — creating and upgrading Kubernetes clusters via `kind: Cluster`
- **Mixed workloads** — a real application (OpenCart) with its database running as a VM and its frontend running as containers in a guest cluster, all load balanced
- **Lifecycle operations** — in-place Kubernetes version upgrade via `kubectl patch`
- **VCFA Provider & Consumer portals** — multi-tenancy, guardrails, and cluster management

## Prerequisites

- A fully configured Cloud & K8S Experience Day lab (Supervisor, VKS, VCFA all operational)
- VCF CLI installed and contexts configured (`supervisor:dev-c5545`, `vks-01`, `vcfa:dev-c5545:default-project`)
- The parent repo's manifests already applied (OpenCart MySQL VM, guest cluster `vks-01`, etc.)

## Files

| File | Purpose |
|---|---|
| `demoscript.md` | Step-by-step demo runbook with all commands |
| `guest-cluster03.yaml` | Guest cluster manifest using an older K8s version (for upgrade demo) |
| `complete-cluster-example.yaml` | Comprehensive cluster YAML showing all available ClusterClass variables |
| `oc-mysql2.yaml` | Second MySQL VM manifest (demonstrates VM Service) |

## Usage

Follow `demoscript.md` in order. The script is designed to flow as a live demo — start the guest cluster creation early (it takes time to provision), then show off other capabilities while it builds.
