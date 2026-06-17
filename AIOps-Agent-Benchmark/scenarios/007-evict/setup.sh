#!/usr/bin/env bash
# setup.sh: Pod evicted repeatedly due to ephemeral-storage limit exceeded.
# log-writer writes ~200KB/s to local log file → exceeds 30Mi limit → evicted → repeats.

set -euo pipefail
CTX="AIOps-Agent-Benchmark"

echo "[007-evict] Creating logging namespace..."
kubectl --context "$CTX" create namespace logging --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

echo "[007-evict] Deploying log-writer with tight ephemeral-storage limit..."
cat <<'EOF' | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-writer
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: log-writer
  template:
    metadata:
      labels:
        app: log-writer
    spec:
      containers:
      - name: log-writer
        image: busybox:1.36
        command: ["/bin/sh", "-c"]
        args:
        - |
          LOG=/tmp/app.log
          echo "Starting log-writer..." >> $LOG
          i=0
          while true; do
            echo "$(date) [INFO] Processing request $i: $(head -c 2048 /dev/urandom | base64)" >> $LOG
            i=$((i+1))
          done
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
            ephemeral-storage: "10Mi"
          limits:
            memory: "64Mi"
            cpu: "100m"
            ephemeral-storage: "30Mi"
EOF

echo "[007-evict] Waiting 90s for eviction to occur..."
sleep 90

echo "[007-evict] Current state:"
kubectl --context "$CTX" get pods -n logging -o wide
echo ""
kubectl --context "$CTX" describe pod -n logging -l app=log-writer \
  | grep -E "Status:|Reason:|Message:|Evict" | head -10
echo ""
echo "[007-evict] Setup complete."
echo "  log-writer evicted repeatedly: writes ~200KB/s, limit=30Mi → evicted in ~2min"
echo "  Symptom: pod Status=Evicted or OOMKilled-like cycle"
echo "  Fix: increase ephemeral-storage limit (e.g. 500Mi) or reduce log verbosity"
