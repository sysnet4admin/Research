#!/usr/bin/env bash
# setup.sh — Inject CrashLoopBackOff state for scenario 002.

set -euo pipefail
CTX="AIOps-Agent-Benchmark"

echo "[002-crashloop] Creating staging namespace..."
kubectl --context "$CTX" create namespace staging --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

echo "[002-crashloop] Deploying worker with bad command (exit 1)..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: staging
spec:
  replicas: 2
  selector:
    matchLabels:
      app: worker
  template:
    metadata:
      labels:
        app: worker
    spec:
      containers:
      - name: worker
        image: busybox:1.36
        command: ["/bin/sh", "-c", "echo 'starting'; exit 1"]
EOF

echo "[002-crashloop] Waiting 30s for CrashLoopBackOff..."
sleep 30

echo "[002-crashloop] Current state:"
kubectl --context "$CTX" get pods -n staging
echo ""
echo "[002-crashloop] Setup complete. Expected: worker pods in CrashLoopBackOff"
