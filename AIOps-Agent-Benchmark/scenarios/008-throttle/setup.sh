#!/usr/bin/env bash
# setup.sh: CPU throttling causes high latency and intermittent 5xx.
# api-gateway has cpu limit=50m; load-gen floods it → throttled → slow/failed responses.

set -euo pipefail
CTX="AIOps-Agent-Benchmark"

echo "[008-throttle] Creating prod namespace..."
kubectl --context "$CTX" create namespace prod --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

echo "[008-throttle] Deploying api-gateway with very low CPU limit (50m)..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: prod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
      - name: api-gateway
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "50m"
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: prod
spec:
  selector:
    app: api-gateway
  ports:
  - port: 80
    targetPort: 80
EOF

echo "[008-throttle] Deploying load generator (sustained high request rate)..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: load-gen
  namespace: prod
spec:
  replicas: 3
  selector:
    matchLabels:
      app: load-gen
  template:
    metadata:
      labels:
        app: load-gen
    spec:
      containers:
      - name: load-gen
        image: busybox:1.36
        command: ["/bin/sh", "-c"]
        args:
        - |
          while true; do
            wget -qO- --timeout=2 http://api-gateway.prod.svc.cluster.local/ \
              > /dev/null 2>&1 || echo "$(date) request failed"
          done
        resources:
          requests:
            memory: "32Mi"
            cpu: "100m"
          limits:
            memory: "64Mi"
            cpu: "200m"
EOF

echo "[008-throttle] Waiting 60s for throttle to build up..."
sleep 60

echo "[008-throttle] Current state:"
kubectl --context "$CTX" get pods -n prod
echo ""
kubectl --context "$CTX" top pods -n prod 2>/dev/null || echo "(metrics not ready yet)"
echo ""
echo "[008-throttle] Setup complete."
echo "  api-gateway cpu limit=50m, 3x load-gen → CPU throttled"
echo "  Symptoms: kubectl top shows CPU near limit, responses slow/failing"
echo "  Fix: increase cpu limit (e.g. 500m)"
