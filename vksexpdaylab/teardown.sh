#!/bin/bash
set -e

# Usage: export DEV_NS=dev-XXXXX && ./teardown.sh
# WARNING: This deletes guest-cluster03, oc-mysql2 VM, and shopping app.

if [ -z "$DEV_NS" ]; then
  echo "ERROR: Set DEV_NS first — export DEV_NS=dev-XXXXX"
  exit 1
fi

cd ~/Documents/Lab/vksdemo-main/

# --- Set context to dev namespace ---
vcf context use supervisor:$DEV_NS

# --- Delete guest cluster (takes ~5-10 min) ---
echo ">>> Deleting guest-cluster03..."
kubectl delete cluster guest-cluster03 -n $DEV_NS --wait=false

# --- Delete shopping app ---
echo ">>> Deleting shopping app..."
kubectl delete -f shopping.yaml --ignore-not-found

# --- Delete second MySQL VM ---
echo ">>> Deleting oc-mysql2 VM..."
kubectl delete -f vksexpdaylab/oc-mysql2.yaml --ignore-not-found

# --- Wait for VM to be fully removed ---
echo ">>> Waiting for oc-mysql2 VM to be deleted..."
kubectl wait --for=delete vm/oc-mysql2 --timeout=300s 2>/dev/null || \
  echo "WARNING: oc-mysql2 may still be deleting — check with: kubectl get vm"

# --- Wait for guest cluster to be fully removed ---
echo ">>> Waiting for guest-cluster03 to be fully deleted (this takes a while)..."
while true; do
  kubectl get cluster guest-cluster03 -n $DEV_NS > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "guest-cluster03 deleted"
    break
  fi
  echo "  Still deleting — waiting 30s..."
  sleep 30
done

echo ""
echo "=== Teardown Complete ==="
echo "Verify:  kubectl get clusters,vm,pods"
