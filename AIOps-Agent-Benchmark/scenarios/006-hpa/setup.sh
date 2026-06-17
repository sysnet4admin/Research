#!/usr/bin/env bash
# setup.sh: HPA configured but not scaling: resource.requests.cpu missing.
# HPA shows <unknown>/50% → never triggers → pods stay at 1 under load.

set -euo pipefail
CTX="AIOps-Agent-Benchmark"

echo "[006-hpa] Creating api namespace..."
kubectl --context "$CTX" create namespace api --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

echo "[006-hpa] Deploying api-server WITHOUT resource requests (HPA trap)..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      containers:
      - name: api-server
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        # No resources.requests set intentionally: HPA cannot compute usage ratio
---
apiVersion: v1
kind: Service
metadata:
  name: api-server
  namespace: api
spec:
  selector:
    app: api-server
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-server
  namespace: api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-server
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
EOF

echo "[006-hpa] Deploying load generator to drive CPU load..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: load-gen
  namespace: api
spec:
  replicas: 1
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
            wget -qO- http://api-server.api.svc.cluster.local/ > /dev/null 2>&1 || true
          done
        resources:
          requests:
            memory: "32Mi"
            cpu: "100m"
          limits:
            memory: "64Mi"
            cpu: "200m"
EOF

echo "[006-hpa] Waiting 60s for HPA to attempt first evaluation..."
sleep 60

echo "[006-hpa] Current state:"
kubectl --context "$CTX" get hpa -n api
echo ""
kubectl --context "$CTX" get pods -n api
echo ""
echo "[006-hpa] Setup complete."
echo "  HPA shows <unknown>/50%: resource.requests.cpu missing → metrics-server cannot compute ratio"
echo "  Load generator running but pod count stays at 1"
