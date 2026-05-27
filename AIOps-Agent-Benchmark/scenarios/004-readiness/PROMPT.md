# Scenario 008 — Service Unreachable: Traffic Not Reaching Pods

## Context

You are an SRE. The `frontend` deployment in the `web` namespace was
just deployed. Pods appear to be running but the service is returning
no responses — users cannot reach the application.

Cluster context: `AIOps-Agent-Benchmark`

## Task

1. Investigate why the `frontend` service has no traffic.
2. Find the root cause — pods look healthy at first glance.
3. Fix the issue so the service correctly routes traffic to pods.
4. Confirm the service has active endpoints and pods are ready.

## Rules

- Use `--context AIOps-Agent-Benchmark` on every kubectl command.
- Do not assume the cause — check both pods AND service state.
- Do not modify anything outside the `web` namespace.
- Do not delete and recreate the Deployment.
