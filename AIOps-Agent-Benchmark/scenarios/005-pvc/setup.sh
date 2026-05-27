#!/usr/bin/env bash
# setup.sh — PVC references a non-existent StorageClass → Pending chain.
# Pod → PVC(Pending) → StorageClass "fast-ssd" not found.

set -euo pipefail
CTX="AIOps-Agent-Benchmark"

echo "[009-pvc] Creating data namespace..."
kubectl --context "$CTX" create namespace data --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

echo "[009-pvc] Creating PVC with non-existent StorageClass..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: data
spec:
  storageClassName: fast-ssd
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

echo "[009-pvc] Deploying db-writer referencing the broken PVC..."
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-writer
  namespace: data
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db-writer
  template:
    metadata:
      labels:
        app: db-writer
    spec:
      containers:
      - name: db-writer
        image: busybox:1.36
        command: ["/bin/sh", "-c", "while true; do echo writing; sleep 5; done"]
        volumeMounts:
        - name: data-vol
          mountPath: /data
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
      volumes:
      - name: data-vol
        persistentVolumeClaim:
          claimName: data-pvc
EOF

echo "[009-pvc] Waiting 20s..."
sleep 20

echo "[009-pvc] Current state:"
kubectl --context "$CTX" get pods -n data
echo ""
kubectl --context "$CTX" get pvc -n data
echo ""
echo "[009-pvc] Setup complete."
echo "  db-writer pod Pending → PVC Pending → StorageClass 'fast-ssd' does not exist"
echo "  Correct StorageClass is: managed-nfs-storage (cluster default)"
