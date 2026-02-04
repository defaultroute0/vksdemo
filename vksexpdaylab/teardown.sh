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

# --- Delete guest cluster (no wait) ---
echo ">>> Deleting guest-cluster03..."
kubectl delete cluster guest-cluster03 -n $DEV_NS --wait=false

# --- Delete shopping app ---
echo ">>> Deleting shopping app..."
kubectl delete -f shopping.yaml --ignore-not-found

# --- Delete second MySQL VM ---
echo ">>> Deleting oc-mysql2 VM..."
kubectl delete -f vksexpdaylab/oc-mysql2.yaml --ignore-not-found

echo ""
echo "=== Teardown Initiated ==="
echo "Deletions continue in the background."
echo "Monitor:  kubectl get clusters,vm,pods"
