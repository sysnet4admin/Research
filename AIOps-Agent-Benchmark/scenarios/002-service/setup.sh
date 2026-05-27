#!/usr/bin/env bash
# setup.sh — Inject wrong Service selector for scenario 005.

set -euo pipefail
CTX="AIOps-Agent-Benchmark"

echo "[005-service] Creating production namespace..."
kubectl --context "$CTX" create namespace production --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

echo "[005-service] Deploying frontend pods (label: app=frontend)..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        version: v1
    spec:
      containers:
      - name: frontend
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
EOF

echo "[005-service] Creating Service with WRONG selector (app=frontend-svc)..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: production
spec:
  selector:
    app: frontend-svc
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

echo "[005-service] Waiting 20s for Pods to start..."
sleep 20

echo "[005-service] Current state:"
kubectl --context "$CTX" get pods,svc,endpoints -n production
echo ""
echo "[005-service] Setup complete."
echo "  Pods label:    app=frontend"
echo "  Service selector: app=frontend-svc (WRONG)"
echo "  Expected: Service has 0 endpoints"
