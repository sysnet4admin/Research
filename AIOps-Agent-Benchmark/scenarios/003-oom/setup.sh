#!/usr/bin/env bash
# setup.sh: Inject OOMKilled state for scenario 003.
# log-collector allocates 120MB but limit is 64Mi → OOMKilled (exit 137).
# Logs are empty (killed during allocation, before any stdout).

set -euo pipefail
CTX="AIOps-Agent-Benchmark"

echo "[003-oom] Creating monitoring namespace..."
kubectl --context "$CTX" create namespace monitoring --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

echo "[003-oom] Deploying log-collector with insufficient memory limit (64Mi)..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-collector
  namespace: monitoring
  annotations:
    description: "Collects and buffers application logs in memory before flushing"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      containers:
      - name: log-collector
        image: python:3.11-slim
        command:
        - /bin/sh
        - -c
        - |
          python3 -c "
          import time
          # Simulate loading 120MB log buffer into memory
          buf = bytearray(120 * 1024 * 1024)
          print('Buffer ready')
          time.sleep(3600)
          "
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "200m"
EOF

echo "[003-oom] Waiting 60s for OOMKilled to manifest..."
sleep 60

echo "[003-oom] Current state:"
kubectl --context "$CTX" get pods -n monitoring
echo ""
kubectl --context "$CTX" describe pod -n monitoring -l app=log-collector \
  | grep -A5 "Last State:" | head -10
echo ""
echo "[003-oom] Setup complete."
echo "  log-collector is OOMKilled (exit code 137): limit=64Mi, needs=120Mi"
echo "  kubectl logs will show NOTHING (killed before stdout)"
echo "  Diagnosis requires: kubectl describe + kubectl top"
