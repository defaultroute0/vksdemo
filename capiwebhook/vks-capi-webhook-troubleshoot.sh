#!/usr/bin/env bash
#
# VKS CAPI Admission Webhook Troubleshooting Script
# ==================================================
# Based on: VKS-CAPI-Webhook-Troubleshooting.md
#
# Runs all diagnostic checks for the "variable is not defined" webhook error
# after a VKS version upgrade on a vSphere Supervisor. Optionally applies
# remediation (controller restarts / cert regeneration).
#
# Usage:
#   ./vks-capi-webhook-troubleshoot.sh [options]
#
# By default (no arguments), runs diagnostics AND restarts controllers (--fix).
#
# Options:
#   --diagnose-only  Run diagnostics only (no restarts, read-only)
#   --fix-cert       Also delete stale cert if VariablesReconciled=False
#   --get-password Show manual steps to retrieve CP VM password; test if current one works
#   --namespace    Override VKS service namespace (default: svc-tkg-domain-c10)
#   --supervisor   Supervisor API VIP (default: 10.1.0.6)
#   --vcenter      vCenter FQDN (default: vc-wld01-a.site-a.vcf.lab)
#   --vc-user      vCenter SSH user (default: root)
#   --vc-password  vCenter SSH password (default: VMware123!VMware123!)
#   --cp-password  Supervisor CP VM root password (default: pre-configured; skips vCenter lookup)
#   --cc-version   ClusterClass version to check (default: builtin-generic-v3.4.0)
#   --help         Show this help message
#
# Ref KBs: 392756, 414721, 423284, 424003

set -euo pipefail

# ─────────────────────────────────────────────
# Defaults
# ─────────────────────────────────────────────
FIX=true
FIX_CERT=false
GET_PASSWORD=false
VKS_NS="svc-tkg-domain-c10"
SUPERVISOR_IP="10.1.0.6"
VCENTER="vc-wld01-a.site-a.vcf.lab"
VC_USER="root"
VC_PASSWORD='VMware123!VMware123!'
CC_VERSION="builtin-generic-v3.4.0"
CC_PUBLIC_NS="vmware-system-vks-public"
CP_VM_IPS=("10.1.1.85" "10.1.1.86" "10.1.1.87" "10.1.1.88")

# ─────────────────────────────────────────────
# Colors / helpers
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

pass()  { echo -e "  ${GREEN}[PASS]${NC}  $*"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}  $*"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
info()  { echo -e "  ${CYAN}[INFO]${NC}  $*"; }
header(){ echo -e "\n${BOLD}═══════════════════════════════════════════════════${NC}"; echo -e "${BOLD}  $*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"; }
divider(){ echo -e "${CYAN}───────────────────────────────────────────────────${NC}"; }

ISSUES_FOUND=0
TOTAL_CHECKS=0

check_result() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [ "$1" -ne 0 ]; then
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    fi
    return 0
}

# ─────────────────────────────────────────────
# SSH helpers for CP VM fallback
# If the CP VM password changes after a Supervisor upgrade,
# retrieve a new one manually:
#   ssh root@<vcenter> → shell → /usr/lib/vmware-wcp/decryptK8Pwd.py
# Then update here or override at runtime with: --cp-password <pw>
# NOTE: VCSA 9.0 appliancesh blocks non-interactive SSH commands,
#       so dynamic retrieval via SSH is not possible.
# ─────────────────────────────────────────────
CP_VM_PASSWORD='rAV&C[D=z|9>?iNC'
CP_VM_CONNECTED=""
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive -o ConnectTimeout=10 -o LogLevel=ERROR"

ensure_cp_vm_access() {
    # Already connected from a previous call?
    [[ -n "${CP_VM_CONNECTED}" ]] && return 0

    # Ensure sshpass is available
    if ! command -v sshpass &>/dev/null; then
        info "Installing sshpass..."
        if ! sudo apt install -y sshpass 2>/dev/null; then
            fail "sshpass not available and could not be installed"
            return 1
        fi
    fi

    if [[ -z "${CP_VM_PASSWORD}" ]]; then
        fail "No CP VM password configured"
        warn "Retrieve it manually: ssh root@${VCENTER} → shell → /usr/lib/vmware-wcp/decryptK8Pwd.py"
        warn "Then re-run with: --cp-password <password>"
        return 1
    fi

    # Try each CP VM IP until one accepts SSH
    export SSHPASS="${CP_VM_PASSWORD}"
    for ip in "${CP_VM_IPS[@]}"; do
        info "Trying SSH to ${ip}..."
        if sshpass -e ssh ${SSH_OPTS} root@"${ip}" "echo ok" 2>/dev/null; then
            CP_VM_CONNECTED="${ip}"
            pass "Connected to CP VM ${ip}"
            return 0
        fi
    done

    fail "Could not SSH into any CP VM (${CP_VM_IPS[*]})"
    warn "Password may have changed after Supervisor upgrade."
    warn "Retrieve new password: ssh root@${VCENTER} → shell → /usr/lib/vmware-wcp/decryptK8Pwd.py"
    warn "Then re-run with: --cp-password <new-password>"
    return 1
}

run_on_cp_vm() {
    sshpass -e ssh ${SSH_OPTS} root@"${CP_VM_CONNECTED}" "$1" 2>&1
}

# Unified kubectl runner: uses SSH if connected to CP VM, otherwise local kubectl.
# Takes the full kubectl command as a single string argument.
USE_SSH=false
run_kubectl() {
    local cmd="$1"
    if $USE_SSH && [[ -n "${CP_VM_CONNECTED}" ]]; then
        run_on_cp_vm "${cmd}"
    else
        eval "${cmd}" 2>/dev/null
    fi
}

# ─────────────────────────────────────────────
# Parse args
# ─────────────────────────────────────────────
usage() {
    sed -n '/^# Usage:/,/^# Ref KBs:/p' "$0" | sed 's/^# //' | head -n -1
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --diagnose-only) FIX=false; FIX_CERT=false; shift ;;
        --fix)        FIX=true;      shift ;;
        --fix-cert)   FIX_CERT=true; FIX=true; shift ;;
        --get-password) GET_PASSWORD=true; shift ;;
        --namespace)  VKS_NS="$2";   shift 2 ;;
        --supervisor) SUPERVISOR_IP="$2"; shift 2 ;;
        --vcenter)    VCENTER="$2";  shift 2 ;;
        --vc-user)    VC_USER="$2";  shift 2 ;;
        --vc-password)VC_PASSWORD="$2"; shift 2 ;;
        --cp-password)CP_VM_PASSWORD="$2"; shift 2 ;;
        --cc-version) CC_VERSION="$2"; shift 2 ;;
        --help|-h)    usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo -e "${BOLD}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   VKS CAPI Admission Webhook Troubleshooting Script         ║"
echo "║   Issue: 'variable is not defined' after VKS upgrade        ║"
echo "║   Ref: KB 392756 / KB 414721 / KB 423284 / KB 424003       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Timestamp:      $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "  Supervisor VIP: ${SUPERVISOR_IP}"
echo "  vCenter:        ${VCENTER}"
echo "  ClusterClass:   ${CC_VERSION}"
echo "  Mode:           $(if $FIX_CERT; then echo 'DIAGNOSE + FIX + CERT REGEN'; elif $FIX; then echo 'DIAGNOSE + FIX'; else echo 'DIAGNOSE ONLY'; fi)"


# ═════════════════════════════════════════════
# STEP 0 (optional): Show how to retrieve Supervisor CP VM Password
# NOTE: VCSA 9.0 appliancesh blocks non-interactive SSH commands,
#       so this can only provide manual instructions.
# ═════════════════════════════════════════════
if $GET_PASSWORD; then
    header "Step 0: Retrieve Supervisor CP VM Root Password"

    divider
    warn "VCSA 9.0 appliancesh blocks non-interactive SSH command execution."
    warn "The CP VM password must be retrieved manually."
    echo ""
    info "Manual steps to retrieve the password:"
    echo ""
    echo "  1. SSH into vCenter:"
    echo "     ssh ${VC_USER}@${VCENTER}"
    echo ""
    echo "  2. At the VCSA appliancesh prompt, switch to bash:"
    echo "     Command> shell"
    echo ""
    echo "  3. Run the password decryption script:"
    echo "     /usr/lib/vmware-wcp/decryptK8Pwd.py"
    echo ""
    echo "  4. Note the PWD value from the output, then re-run this script:"
    echo "     $0 --cp-password <the-password>"
    echo ""
    echo "  Or update the CP_VM_PASSWORD variable in this script (line ~83)."
    echo ""

    if [[ -n "${CP_VM_PASSWORD}" ]]; then
        info "Current hardcoded password: ${CP_VM_PASSWORD}"
        info "Testing if it still works..."
        echo ""

        if command -v sshpass &>/dev/null; then
            export SSHPASS="${CP_VM_PASSWORD}"
            PASS_WORKS=false
            for ip in "${CP_VM_IPS[@]}"; do
                if sshpass -e ssh ${SSH_OPTS} root@"${ip}" "echo ok" 2>/dev/null; then
                    pass "Hardcoded password works on CP VM ${ip}"
                    PASS_WORKS=true
                    break
                fi
            done
            if ! $PASS_WORKS; then
                fail "Hardcoded password no longer works on any CP VM"
                warn "Password has likely changed — follow the manual steps above"
            fi
        else
            warn "sshpass not installed, cannot test password"
        fi
    fi
fi


# ═════════════════════════════════════════════
# STEP 1: Verify Supervisor Connectivity
# ═════════════════════════════════════════════
header "Step 1: Verify Connectivity"

# Ping Supervisor API VIP
divider
echo "  Pinging Supervisor API VIP (${SUPERVISOR_IP})..."
if ping -c 3 -W 3 "${SUPERVISOR_IP}" &>/dev/null; then
    pass "Supervisor API VIP (${SUPERVISOR_IP}) is reachable"
    check_result 0
else
    fail "Supervisor API VIP (${SUPERVISOR_IP}) is NOT reachable"
    check_result 1 || true
fi

# curl Supervisor API
echo "  Testing Supervisor HTTPS API (port 6443)..."
if curl -sk --connect-timeout 5 "https://${SUPERVISOR_IP}:6443/api" &>/dev/null; then
    pass "Supervisor API (https://${SUPERVISOR_IP}:6443/api) responding"
    check_result 0
else
    warn "Supervisor API on port 6443 not responding (may use 443 instead)"
    if curl -sk --connect-timeout 5 "https://${SUPERVISOR_IP}:443" &>/dev/null; then
        pass "Supervisor API (https://${SUPERVISOR_IP}:443) responding"
        check_result 0
    else
        fail "Supervisor API not responding on 6443 or 443"
        check_result 1 || true
    fi
fi

# Ping vCenter
echo "  Pinging vCenter (${VCENTER})..."
if ping -c 3 -W 3 "${VCENTER}" &>/dev/null; then
    pass "vCenter (${VCENTER}) is reachable"
    check_result 0
else
    fail "vCenter (${VCENTER}) is NOT reachable"
    check_result 1 || true
fi

# curl vCenter HTTPS
echo "  Testing vCenter HTTPS..."
if curl -sk --connect-timeout 5 "https://${VCENTER}" &>/dev/null; then
    pass "vCenter HTTPS responding"
    check_result 0
else
    fail "vCenter HTTPS not responding"
    check_result 1 || true
fi


# ═════════════════════════════════════════════
# STEP 2: Check kubectl Context
# ═════════════════════════════════════════════
header "Step 2: Check kubectl Context"

divider
echo "  Current kubectl contexts:"
kubectl config get-contexts 2>/dev/null || { fail "kubectl not configured or not available"; exit 1; }
echo ""

CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "NONE")
info "Active context: ${CURRENT_CTX}"

if [[ "${CURRENT_CTX}" == *"supervisor"* ]] || [[ "${CURRENT_CTX}" == *"Supervisor"* ]]; then
    pass "Context appears to be a Supervisor context"
    check_result 0
else
    warn "Context '${CURRENT_CTX}' may not be a Supervisor context"
    warn "If checks fail, try: kubectl config use-context supervisor"
    check_result 0
fi


# ═════════════════════════════════════════════
# STEP 2b: Auto-detect VKS Service Namespace
# ═════════════════════════════════════════════
if [[ -z "${VKS_NS}" ]]; then
    divider
    echo "  Auto-detecting VKS service namespace..."
    VKS_NS=$(kubectl get ns --no-headers 2>/dev/null | awk '{print $1}' | grep '^svc-tkg-domain' | head -1 || true)
    if [[ -z "${VKS_NS}" ]]; then
        fail "Could not auto-detect VKS service namespace (no 'svc-tkg-domain*' namespace found)"
        warn "Specify manually with --namespace <ns>"
        exit 1
    fi
    pass "Auto-detected VKS namespace: ${VKS_NS}"
else
    info "Using namespace: ${VKS_NS}"
fi
echo ""

# ═════════════════════════════════════════════
# STEP 2c: Detect kubectl access level & establish SSH if needed
# ═════════════════════════════════════════════
divider
echo "  Testing kubectl cluster-wide access..."
if kubectl get clusterclass -A --no-headers &>/dev/null 2>&1; then
    pass "Local kubectl has cluster-wide access"
else
    warn "Local kubectl is namespace-scoped (cannot see cluster-wide resources)"
    info "Establishing SSH to Supervisor CP VM for full diagnostics..."
    echo ""
    if ensure_cp_vm_access; then
        USE_SSH=true
        info "All diagnostic commands will run via SSH on ${CP_VM_CONNECTED}"
    else
        warn "SSH fallback not available — some diagnostic checks will be limited"
    fi
fi
echo ""


# ═════════════════════════════════════════════
# STEP 3: Check ClusterClass Availability
# ═════════════════════════════════════════════
header "Step 3: Check ClusterClass Availability"

divider
echo "  Listing all ClusterClasses across namespaces..."
echo ""
run_kubectl "kubectl get clusterclass -A" || warn "Could not list ClusterClasses"
echo ""

# Check v3.4.0 in public namespace
echo "  Checking ${CC_VERSION} in ${CC_PUBLIC_NS}..."
if run_kubectl "kubectl get clusterclass ${CC_VERSION} -n ${CC_PUBLIC_NS}" &>/dev/null; then
    pass "${CC_VERSION} exists in ${CC_PUBLIC_NS}"
    check_result 0
else
    fail "${CC_VERSION} NOT found in ${CC_PUBLIC_NS}"
    fail "VKS 3.4.0 may not have been installed or reconciliation is incomplete"
    check_result 1 || true
fi

# Show ClusterClass details
divider
echo "  ClusterClass description (first 40 lines):"
CC_DESC=$(run_kubectl "kubectl describe clusterclass ${CC_VERSION} -n ${CC_PUBLIC_NS}" || true)
if [[ -n "${CC_DESC}" ]]; then
    echo "${CC_DESC}" | head -40
else
    warn "Could not describe ${CC_VERSION}"
fi
echo ""


# ═════════════════════════════════════════════
# STEP 4: Check TKR / Kubernetes Releases
# ═════════════════════════════════════════════
header "Step 4: Check Available Kubernetes Releases"

divider
echo "  TanzuKubernetesReleases (READY=True):"
echo ""
TKR_OUTPUT=$(run_kubectl "kubectl get tanzukubernetesreleases" || true)
echo "${TKR_OUTPUT}" | head -1
echo "${TKR_OUTPUT}" | grep -i true || warn "No READY TKRs found"
echo ""

READY_COUNT=$(echo "${TKR_OUTPUT}" | grep -ci true || echo 0)
READY_COUNT=$(echo "${READY_COUNT}" | awk '{s+=$1} END {print s+0}')
if [[ "${READY_COUNT}" -gt 0 ]]; then
    pass "${READY_COUNT} TKR(s) in READY state"
    check_result 0
else
    fail "No TKRs in READY state"
    check_result 1 || true
fi


# ═════════════════════════════════════════════
# STEP 5: Check Existing Clusters
# ═════════════════════════════════════════════
header "Step 5: Check Existing Clusters"

divider
echo "  All CAPI clusters:"
echo ""
run_kubectl "kubectl get clusters -A" || warn "Could not list clusters"
echo ""

# Iterate clusters and show phase
while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    CL_NS=$(echo "${line}" | awk '{print $1}')
    CL_NAME=$(echo "${line}" | awk '{print $2}')
    CL_PHASE=$(run_kubectl "kubectl get cluster ${CL_NAME} -n ${CL_NS} -o jsonpath='{.status.phase}'" || echo "Unknown")
    CL_CC=$(run_kubectl "kubectl get cluster ${CL_NAME} -n ${CL_NS} -o jsonpath='{.spec.topology.class}'" || echo "Unknown")

    if [[ "${CL_PHASE}" == "Provisioned" ]]; then
        pass "Cluster ${CL_NAME} (${CL_NS}): phase=${CL_PHASE}, class=${CL_CC}"
    elif [[ "${CL_PHASE}" == "Provisioning" ]]; then
        warn "Cluster ${CL_NAME} (${CL_NS}): phase=${CL_PHASE}, class=${CL_CC}"
    else
        fail "Cluster ${CL_NAME} (${CL_NS}): phase=${CL_PHASE}, class=${CL_CC}"
    fi
done < <(run_kubectl "kubectl get clusters -A --no-headers" || true)
echo ""


# ═════════════════════════════════════════════
# STEP 6: Check CAPI Controller Status
# ═════════════════════════════════════════════
header "Step 6: Check CAPI Controller Status"

divider
echo "  Deployments in ${VKS_NS}:"
echo ""
run_kubectl "kubectl get deployments -n ${VKS_NS}" || warn "Could not list deployments"
echo ""

# Check each deployment for readiness
UNHEALTHY_DEPLOYMENTS=0
DEPLOYMENT_COUNT=0
while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    DEPLOYMENT_COUNT=$((DEPLOYMENT_COUNT + 1))
    DEP_NAME=$(echo "${line}" | awk '{print $1}')
    DEP_READY=$(echo "${line}" | awk '{print $2}')
    DESIRED=$(echo "${DEP_READY}" | cut -d'/' -f2)
    ACTUAL=$(echo "${DEP_READY}" | cut -d'/' -f1)

    if [[ "${ACTUAL}" == "${DESIRED}" ]]; then
        pass "${DEP_NAME}: ${DEP_READY}"
    else
        fail "${DEP_NAME}: ${DEP_READY} (not fully ready)"
        UNHEALTHY_DEPLOYMENTS=$((UNHEALTHY_DEPLOYMENTS + 1))
    fi
done < <(run_kubectl "kubectl get deployments -n ${VKS_NS} --no-headers" || true)

if [[ ${DEPLOYMENT_COUNT} -eq 0 ]]; then
    warn "Could not retrieve deployment status (RBAC or namespace access issue)"
    check_result 1 || true
elif [[ ${UNHEALTHY_DEPLOYMENTS} -eq 0 ]]; then
    check_result 0
    pass "All ${DEPLOYMENT_COUNT} deployments healthy"
else
    check_result 1 || true
    fail "${UNHEALTHY_DEPLOYMENTS} of ${DEPLOYMENT_COUNT} deployment(s) not fully ready"
fi
echo ""

# Check CAPW / CAPV pods
divider
echo "  CAPW pods (vmware-system-capw):"
run_kubectl "kubectl get pods -n vmware-system-capw" || warn "Could not list CAPW pods"
echo ""
echo "  CAPV pods (vmware-system-capv):"
run_kubectl "kubectl get pods -n vmware-system-capv" || warn "Could not list CAPV pods"
echo ""


# ═════════════════════════════════════════════
# STEP 7: Check Webhook Configuration
# ═════════════════════════════════════════════
header "Step 7: Check Webhook Configuration"

divider
echo "  Mutating webhooks (CAPI/TKG-related):"
MWH_OUTPUT=$(run_kubectl "kubectl get mutatingwebhookconfigurations" 2>&1 || true)
if echo "${MWH_OUTPUT}" | grep -qi "forbidden\|cannot"; then
    warn "Insufficient RBAC to list mutating webhooks"
else
    echo "${MWH_OUTPUT}" | grep -iE "NAME|capi|tkg|tanzu" || warn "No CAPI/TKG mutating webhooks found"
fi
echo ""

echo "  Validating webhooks (CAPI/TKG-related):"
VWH_OUTPUT=$(run_kubectl "kubectl get validatingwebhookconfigurations" 2>&1 || true)
if echo "${VWH_OUTPUT}" | grep -qi "forbidden\|cannot"; then
    warn "Insufficient RBAC to list validating webhooks"
else
    echo "${VWH_OUTPUT}" | grep -iE "NAME|capi|tkg|tanzu" || warn "No CAPI/TKG validating webhooks found"
fi
echo ""


# ═════════════════════════════════════════════
# STEP 8: Check VM Classes and Storage Classes
# ═════════════════════════════════════════════
header "Step 8: Check VM Classes and Storage Classes"

divider
echo "  Storage classes:"
run_kubectl "kubectl get storageclasses" || warn "Could not list storage classes"
echo ""

echo "  VM classes (first 20):"
VM_CLASSES=$(run_kubectl "kubectl get virtualmachineclasses --no-headers" || true)
echo "${VM_CLASSES}" | head -20
[[ -z "${VM_CLASSES}" ]] && warn "Could not list VM classes"
echo ""


# ═════════════════════════════════════════════
# STEP 9: Check VKS Package Installation Status
# ═════════════════════════════════════════════
header "Step 9: Check VKS Package Installation Status"

divider
echo "  VKS-related package installs:"
run_kubectl "kubectl get packageinstalls -A" | grep -E "NAME|vks|tkg|svc-tkg" || warn "No VKS package installs found"
echo ""

echo "  VKS-related kapp apps:"
run_kubectl "kubectl get apps -A" | grep -E "NAME|vks|tkg|svc-tkg" || warn "No VKS kapp apps found"
echo ""

# Check reconciliation status
RECONCILE_LINE=$(run_kubectl "kubectl get packageinstalls -A --no-headers" | grep "svc-tkg\.vsphere\.vmware\.com" | head -1 || echo "")
if echo "${RECONCILE_LINE}" | grep -qi "Reconcile succeeded"; then
    pass "VKS package reconciliation: Reconcile succeeded"
    check_result 0
elif [[ -z "${RECONCILE_LINE}" ]]; then
    warn "Could not find svc-tkg package install"
    check_result 1 || true
else
    RECONCILE_DESC=$(echo "${RECONCILE_LINE}" | awk '{for(i=6;i<=NF;i++) printf "%s ",$i; print ""}')
    warn "VKS package reconciliation status: ${RECONCILE_DESC}"
    check_result 1 || true
fi
echo ""


# ═════════════════════════════════════════════
# STEP 10: Key Diagnostic Checks (KB 424003 / KB 423284)
# ═════════════════════════════════════════════
header "Step 10: Key Diagnostic Checks"

# 10a. VariablesReconciled condition
divider
echo "  Checking ClusterClass VariablesReconciled condition..."

VARS_RECONCILED="Unknown"
CC_CONDITIONS=$(run_kubectl "kubectl get clusterclass ${CC_VERSION} -n ${CC_PUBLIC_NS} -o jsonpath='{.status.conditions}'" 2>/dev/null || echo "")
# Fallback: try VKS service namespace if public namespace didn't work
if [[ -z "${CC_CONDITIONS}" ]] || echo "${CC_CONDITIONS}" | grep -qi "NotFound\|error"; then
    CC_CONDITIONS=$(run_kubectl "kubectl get clusterclass ${CC_VERSION} -n ${VKS_NS} -o jsonpath='{.status.conditions}'" 2>/dev/null || echo "")
fi
# Strip any leading/trailing single quotes from jsonpath output
CC_CONDITIONS=$(echo "${CC_CONDITIONS}" | sed "s/^'//;s/'$//")

if [[ -n "${CC_CONDITIONS}" ]] && ! echo "${CC_CONDITIONS}" | grep -qi "NotFound\|error"; then
    if command -v jq &>/dev/null; then
        echo "${CC_CONDITIONS}" | jq '.' 2>/dev/null || echo "${CC_CONDITIONS}"
        VARS_RECONCILED=$(echo "${CC_CONDITIONS}" | jq -r '.[] | select(.type=="VariablesReconciled") | .status' 2>/dev/null || echo "Unknown")
    else
        echo "${CC_CONDITIONS}"
        VARS_RECONCILED=$(echo "${CC_CONDITIONS}" | grep -oP '"type":"VariablesReconciled".*?"status":"[^"]*"' | grep -oP 'status":"[^"]*' | cut -d'"' -f2 || echo "Unknown")
    fi
fi

echo ""
if [[ "${VARS_RECONCILED}" == "True" ]]; then
    pass "VariablesReconciled = True"
    check_result 0
elif [[ "${VARS_RECONCILED}" == "False" ]]; then
    fail "VariablesReconciled = False"
    fail "This is the ROOT CAUSE - webhook cert is likely stale (KB 424003)"
    fail "Use --fix-cert to delete the cert secret and restart controllers"
    check_result 1 || true
else
    warn "Could not determine VariablesReconciled status (got: ${VARS_RECONCILED})"
    check_result 1 || true
fi

# 10b. Check runtime-extension logs for x509 errors
divider
echo "  Checking runtime-extension-controller-manager logs for cert errors..."
CERT_ERRORS=$(run_kubectl "kubectl logs -n ${VKS_NS} -l app=runtime-extension-controller-manager --tail=100" | grep -c "x509" || true)
CERT_ERRORS=${CERT_ERRORS:-0}
# Ensure it's a single integer (grep -c across multiple containers can produce multiple lines)
CERT_ERRORS=$(echo "${CERT_ERRORS}" | awk '{s+=$1} END {print s+0}')

if [[ "${CERT_ERRORS}" -gt 0 ]]; then
    fail "Found ${CERT_ERRORS} x509 certificate error(s) in runtime-extension logs"
    fail "Stale TLS cert detected (KB 423284 / KB 424003)"
    check_result 1 || true
    echo ""
    echo "  Last 5 x509-related log lines:"
    run_kubectl "kubectl logs -n ${VKS_NS} -l app=runtime-extension-controller-manager --tail=200" | grep "x509" | tail -5
else
    pass "No x509 certificate errors in runtime-extension logs"
    check_result 0
fi
echo ""

# 10c. Check webhook certificate validity
divider
echo "  Checking webhook certificate validity..."
CERT_DATA=$(run_kubectl "kubectl get secret runtime-extension-webhook-service-cert -n ${VKS_NS} -o jsonpath='{.data.ca\\.crt}'" || echo "")

if [[ -n "${CERT_DATA}" ]]; then
    CERT_INFO=$(echo "${CERT_DATA}" | base64 -d 2>/dev/null | openssl x509 -noout -dates -serial 2>/dev/null || echo "DECODE_ERROR")

    if [[ "${CERT_INFO}" == "DECODE_ERROR" ]]; then
        warn "Could not decode webhook certificate"
        check_result 1 || true
    else
        echo "  ${CERT_INFO}"
        echo ""

        # Extract notAfter and check if cert is expired
        NOT_AFTER=$(echo "${CERT_INFO}" | grep "notAfter" | cut -d'=' -f2)
        if [[ -n "${NOT_AFTER}" ]]; then
            EXPIRY_EPOCH=$(date -d "${NOT_AFTER}" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(date +%s)
            DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

            if [[ ${DAYS_LEFT} -lt 0 ]]; then
                fail "Webhook certificate is EXPIRED (expired ${NOT_AFTER})"
                check_result 1 || true
            elif [[ ${DAYS_LEFT} -lt 14 ]]; then
                warn "Webhook certificate expires in ${DAYS_LEFT} days (${NOT_AFTER})"
                warn "Per KB 424003, cert rotation bug recurs every ~60 days"
                check_result 1 || true
            else
                pass "Webhook certificate valid for ${DAYS_LEFT} more days (expires ${NOT_AFTER})"
                check_result 0
            fi
        fi
    fi
else
    warn "Could not retrieve runtime-extension-webhook-service-cert secret"
    check_result 1 || true
fi
echo ""


# ═════════════════════════════════════════════
# STEP 11: Verification - Cluster Health
# ═════════════════════════════════════════════
header "Step 11: Cluster Health Verification"

divider
while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    CL_NS=$(echo "${line}" | awk '{print $1}')
    CL_NAME=$(echo "${line}" | awk '{print $2}')

    echo "  --- Cluster: ${CL_NAME} (${CL_NS}) ---"

    echo "  Machines:"
    run_kubectl "kubectl get machines -n ${CL_NS}" | grep -E "NAME|${CL_NAME}" || echo "    (none)"

    echo "  Control Plane:"
    run_kubectl "kubectl get kubeadmcontrolplanes -n ${CL_NS}" | grep -E "NAME|${CL_NAME}" || echo "    (none)"

    echo "  Machine Deployments:"
    run_kubectl "kubectl get machinedeployments -n ${CL_NS}" | grep -E "NAME|${CL_NAME}" || echo "    (none)"

    echo "  Recent events (last 10):"
    run_kubectl "kubectl get events -n ${CL_NS} --sort-by='.lastTimestamp' --no-headers" | tail -10 || echo "    (none)"
    echo ""
done < <(run_kubectl "kubectl get clusters -A --no-headers" || true)


# ═════════════════════════════════════════════
# SUMMARY
# ═════════════════════════════════════════════
header "Diagnostic Summary"

echo ""
echo "  Total checks run:   ${TOTAL_CHECKS}"
if [[ ${ISSUES_FOUND} -eq 0 ]]; then
    echo -e "  Issues found:        ${GREEN}0${NC}"
    echo ""
    pass "ALL SYSTEMS HEALTHY - No webhook issues detected"
    echo ""
    info "The VKS 3.4.0 reconciliation appears complete."
    info "If you still see webhook errors, they may have self-resolved."
else
    echo -e "  Issues found:        ${RED}${ISSUES_FOUND}${NC}"
    echo ""
    fail "${ISSUES_FOUND} issue(s) detected - see details above"
fi
echo ""


# ═════════════════════════════════════════════
# REMEDIATION (if --fix or --fix-cert)
# ═════════════════════════════════════════════
if $FIX; then
    header "Remediation: Restarting Controllers"
    echo ""

    # Ensure SSH is available if not already established during diagnostics
    if ! $USE_SSH; then
        info "Trying kubectl rollout restart from current context..."
        echo ""
    fi

    echo "  1/3: Restarting vmware-system-tkg-webhook..."
    if run_kubectl "kubectl rollout restart deployment vmware-system-tkg-webhook -n ${VKS_NS}"; then
        pass "vmware-system-tkg-webhook restart initiated"
    else
        fail "Failed to restart vmware-system-tkg-webhook"
    fi

    echo "  2/3: Restarting runtime-extension-controller-manager..."
    if run_kubectl "kubectl rollout restart deployment runtime-extension-controller-manager -n ${VKS_NS}"; then
        pass "runtime-extension-controller-manager restart initiated"
    else
        fail "Failed to restart runtime-extension-controller-manager"
    fi

    echo "  3/3: Restarting capi-controller-manager..."
    if run_kubectl "kubectl rollout restart deployment capi-controller-manager -n ${VKS_NS}"; then
        pass "capi-controller-manager restart initiated"
    else
        fail "Failed to restart capi-controller-manager"
    fi

    echo ""
    info "Waiting 30 seconds for rollouts to progress..."
    sleep 30

    # ── --fix-cert: check VariablesReconciled and delete cert if needed ──
    if $FIX_CERT; then
        echo ""
        divider

        # Re-check VariablesReconciled after restart
        NEW_VARS=$(run_kubectl "kubectl get clusterclass ${CC_VERSION} -n ${CC_PUBLIC_NS} -o jsonpath='{.status.conditions}'" 2>/dev/null || echo "")

        NEW_VARS_STATUS="Unknown"
        if [[ -n "${NEW_VARS}" ]]; then
            if command -v jq &>/dev/null; then
                NEW_VARS_STATUS=$(echo "${NEW_VARS}" | jq -r '.[] | select(.type=="VariablesReconciled") | .status' 2>/dev/null || echo "Unknown")
            else
                NEW_VARS_STATUS=$(echo "${NEW_VARS}" | grep -oP '"type":"VariablesReconciled".*?"status":"[^"]*"' | grep -oP 'status":"[^"]*' | cut -d'"' -f2 || echo "Unknown")
            fi
        fi

        if [[ "${NEW_VARS_STATUS}" != "True" ]]; then
            header "Remediation: Certificate Regeneration (KB 424003)"
            echo ""
            warn "VariablesReconciled is still not True (${NEW_VARS_STATUS}) after restart"
            info "Deleting stale cert secret to force regeneration..."
            echo ""

            echo "  Deleting runtime-extension-webhook-service-cert..."
            run_kubectl "kubectl delete secret runtime-extension-webhook-service-cert -n ${VKS_NS}" && \
                pass "Certificate secret deleted" || warn "Could not delete cert secret (may not exist)"

            echo "  Re-restarting runtime-extension-controller-manager..."
            run_kubectl "kubectl rollout restart deployment runtime-extension-controller-manager -n ${VKS_NS}" && \
                pass "runtime-extension-controller-manager restart initiated" || fail "Failed to restart"

            echo "  Re-restarting capi-controller-manager..."
            run_kubectl "kubectl rollout restart deployment capi-controller-manager -n ${VKS_NS}" && \
                pass "capi-controller-manager restart initiated" || fail "Failed to restart"

            echo ""
            info "Waiting 30 seconds for cert regeneration and rollout..."
            sleep 30
        else
            pass "VariablesReconciled = True after restart, cert deletion not needed"
        fi
    fi

    # ── Post-fix verification ──
    header "Post-Fix Verification"
    echo ""

    VIA_LABEL=""
    $USE_SSH && VIA_LABEL=" (via SSH)"

    echo "  Deployment status in ${VKS_NS}${VIA_LABEL}:"
    run_kubectl "kubectl get deployments -n ${VKS_NS}" || warn "Could not get deployments"
    echo ""

    echo "  ClusterClass conditions${VIA_LABEL}:"
    COND_OUTPUT=$(run_kubectl "kubectl get clusterclass ${CC_VERSION} -n ${CC_PUBLIC_NS} -o jsonpath='{.status.conditions}'" 2>/dev/null || echo "")
    if [[ -n "${COND_OUTPUT}" ]] && command -v jq &>/dev/null; then
        echo "${COND_OUTPUT}" | jq '.' 2>/dev/null || echo "${COND_OUTPUT}"
    else
        echo "  ${COND_OUTPUT:-"(could not retrieve)"}"
    fi
    echo ""

    echo "  Clusters${VIA_LABEL}:"
    run_kubectl "kubectl get clusters -A" || warn "Could not get clusters"
    echo ""

    info "If cluster creation still fails, wait a few more minutes for the cache to fully refresh."
    info "If the problem persists after 10 minutes, check the troubleshooting doc for manual steps."
else
    echo ""
    if [[ ${ISSUES_FOUND} -gt 0 ]]; then
        divider
        echo ""
        info "To apply the fix, re-run with --fix:"
        echo ""
        echo "    $0 --fix"
        echo ""
        info "If VariablesReconciled=False persists, use --fix-cert:"
        echo ""
        echo "    $0 --fix-cert"
        echo ""
    fi
fi

echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Script complete. $(date -u '+%Y-%m-%dT%H:%M:%SZ')${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo ""
