# Scenario 012 — Intermittent Failures and High Latency

## Context

You are an SRE. The `api-gateway` deployment in the `prod` namespace
is experiencing intermittent request failures and high response
latency under load. Pods are Running and no crash loops are observed.
The on-call alert says "elevated error rate and p99 latency spike."

Cluster context: `AIOps-Agent-Benchmark`

## Task

1. Investigate the cause of failures and high latency.
2. Rule out possible causes systematically — pods are running,
   no OOM, no crash loops.
3. Identify the actual bottleneck from available cluster metrics.
4. Fix the issue and confirm stable responses under load.

## Rules

- Use `--context AIOps-Agent-Benchmark` on every kubectl command.
- Use cluster-native observability (kubectl top, describe, events).
- Do not modify anything outside the `prod` namespace.
- Do not delete and recreate the Deployment.
