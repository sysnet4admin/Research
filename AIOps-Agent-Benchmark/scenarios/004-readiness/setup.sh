#!/usr/bin/env bash
# setup.sh — Readiness probe misconfigured: pod Running but endpoint = 0.
# Probe checks /healthz but nginx only serves /  → 404 → not ready → no traffic.

set -euo pipefail
CTX="AIOps-Agent-Benchmark"

echo "[008-readiness] Creating web namespace..."
kubectl --context "$CTX" create namespace web --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

echo "[008-readiness] Deploying frontend with wrong readiness probe path..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
          failureThreshold: 3
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: web
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
EOF

echo "[008-readiness] Waiting 40s for probe cycle..."
sleep 40

echo "[008-readiness] Current state:"
kubectl --context "$CTX" get pods -n web
echo ""
kubectl --context "$CTX" get endpoints -n web
echo ""
echo "[008-readiness] Setup complete."
echo "  Pods are Running but 0/1 READY — readiness probe fails on /healthz (404)"
echo "  Service has 0 endpoints → no traffic reaches the pod"
