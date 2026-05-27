# Scenario 009 — Pod Stuck Pending: Storage Not Provisioned

## Context

You are an SRE. The `db-writer` deployment in the `data` namespace
has been Pending since it was deployed 10 minutes ago.
No pods are running.

Cluster context: `AIOps-Agent-Benchmark`

## Task

1. Investigate why `db-writer` pods are stuck in Pending.
2. Trace the root cause through all relevant K8s resources.
3. Fix the issue so the pod can start successfully.
4. Confirm the pod reaches Running state.

## Rules

- Use `--context AIOps-Agent-Benchmark` on every kubectl command.
- Do not assume the cause — follow the evidence chain.
- Do not modify anything outside the `data` namespace.
