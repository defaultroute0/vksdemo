#!/bin/bash
set -e

# Usage: export DEV_NS=dev-XXXXX && ./setup.sh
# Ensure the $DEV_NS namespace CPU limit is set to 30 GHz in vSphere Client before running.

if [ -z "$DEV_NS" ]; then
  echo "ERROR: Set DEV_NS first — export DEV_NS=dev-XXXXX"
  exit 1
fi

cd ~/Documents/Lab/vksdemo-main/

# --- Set context to dev namespace ---
vcf context use supervisor:$DEV_NS

# --- Deploy guest cluster (takes ~15-20 min) ---
echo ">>> Creating guest-cluster03..."
kubectl apply -f vksexpdaylab/guest-cluster03.yaml

# --- Deploy shopping app (vSphere Pods) ---
echo ">>> Deploying shopping app..."
kubectl apply -f shopping.yaml

# --- Deploy second MySQL VM ---
echo ">>> Creating oc-mysql2 VM..."
kubectl apply -f vksexpdaylab/oc-mysql2.yaml

# --- Wait for shopping app pods to be ready ---
echo ">>> Waiting for shopping app pods..."
kubectl wait --for=condition=Ready pod -l app=shopping --timeout=300s 2>/dev/null || \
  echo "WARNING: Shopping pods not ready yet — check with: kubectl get pods"

# --- Wait for oc-mysql2 VM to be powered on ---
echo ">>> Waiting for oc-mysql2 VM to power on..."
while true; do
  STATE=$(kubectl get vm oc-mysql2 -o jsonpath='{.status.powerState}' 2>/dev/null)
  if [ "$STATE" = "PoweredOn" ]; then
    echo "oc-mysql2 is PoweredOn"
    break
  fi
  echo "  VM state: $STATE — waiting 15s..."
  sleep 15
done

# --- Wait for guest-cluster03 to be ready ---
echo ">>> Waiting for guest-cluster03 to provision (this takes a while)..."
while true; do
  PHASE=$(kubectl get cluster guest-cluster03 -n $DEV_NS -o jsonpath='{.status.phase}' 2>/dev/null)
  if [ "$PHASE" = "Provisioned" ]; then
    echo "guest-cluster03 is Provisioned"
    break
  fi
  echo "  Cluster phase: $PHASE — waiting 30s..."
  sleep 30
done

echo ""
echo "=== Setup Complete ==="
echo "Shopping app:    kubectl get svc"
echo "VMs:             kubectl get vm"
echo "Guest cluster:   kubectl get cluster guest-cluster03 -n $DEV_NS"
