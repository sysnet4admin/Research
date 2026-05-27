#!/usr/bin/env bash
# setup.sh — order-service CrashLoops: DB_HOST=db-prod.internal NXDOMAIN.
# K8s cluster is healthy. Fix requires external infrastructure team.

set -euo pipefail
CTX="AIOps-Agent-Benchmark"

echo "[013-ext-dep] Creating orders namespace..."
kubectl --context "$CTX" create namespace orders --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

echo "[013-ext-dep] Deploying order-service with broken external DB dependency..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: orders
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
      - name: order-service
        image: python:3.11-alpine
        env:
        - name: DB_HOST
          value: "db-prod.internal"
        - name: DB_PORT
          value: "5432"
        command: ["/bin/sh", "-c"]
        args:
        - |
          python3 -c "
          import socket, os, sys
          host = os.environ['DB_HOST']
          port = int(os.environ['DB_PORT'])
          print(f'[order-service] Connecting to {host}:{port}', flush=True)
          try:
              s = socket.create_connection((host, port), timeout=5)
              s.close()
              print('[order-service] DB connected. Ready.', flush=True)
              import time
              while True: time.sleep(60)
          except Exception as e:
              print(f'[order-service] FATAL: DB connection failed: {e}', file=sys.stderr, flush=True)
              sys.exit(1)
          "
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
EOF

echo "[013-ext-dep] Waiting 30s for CrashLoopBackOff..."
sleep 30

echo "[013-ext-dep] Current state:"
kubectl --context "$CTX" get pods -n orders
echo ""
echo "[013-ext-dep] Setup complete."
echo "  order-service CrashLoop: db-prod.internal NXDOMAIN → K8s healthy, issue is external"
