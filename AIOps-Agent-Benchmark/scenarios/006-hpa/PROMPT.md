# Scenario 006: HPA Not Scaling Under Load

## Context

You are an SRE. The `api-server` deployment in the `api` namespace
has an HPA configured to scale up when CPU exceeds 50%.
A load generator is running and CPU is clearly elevated,
but the pod count has not increased beyond 1.

Cluster context: `AIOps-Agent-Benchmark`

## Task

1. Investigate why the HPA is not triggering a scale-out.
2. Identify the root cause: check HPA status and all related resources.
3. Fix the issue so the HPA can correctly evaluate and scale.
4. Confirm HPA shows a valid CPU metric (not `<unknown>`) and
   scales up under load.

## Rules

- Use `--context AIOps-Agent-Benchmark` on every kubectl command.
- Do not disable or delete the HPA: fix the underlying cause.
- Do not modify anything outside the `api` namespace.
