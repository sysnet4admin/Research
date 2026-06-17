# Scenario 002: Service Not Reaching Pods (Wrong Selector)

## Context

You are an SRE. The `frontend` Service in the `production` namespace
is not routing traffic to any Pods. The Pods are Running but
the Service has no Endpoints.

Cluster context: `AIOps-Agent-Benchmark`

## Task

1. Investigate why the `frontend` Service has no active Endpoints.
2. Identify the misconfiguration (do not assume: inspect both the Service and the Pods).
3. Fix the Service so it correctly selects the running Pods.
4. Confirm the Service has active Endpoints.

## Rules

- Use `--context AIOps-Agent-Benchmark` on every kubectl command.
- Inspect both the Service selector and Pod labels **before** making changes.
- Fix the Service selector: do not change Pod labels.
- Do not modify anything outside the `production` namespace.
