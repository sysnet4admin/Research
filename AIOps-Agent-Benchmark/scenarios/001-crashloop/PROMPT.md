# Scenario 001: CrashLoopBackOff Diagnosis and Fix

## Context

You are an SRE. A deployment named `worker` in the `staging` namespace
is in CrashLoopBackOff. An alert just fired.

Cluster context: `AIOps-Agent-Benchmark`

## Task

1. Investigate why the `worker` Pods are crash-looping.
2. Identify the root cause from logs and/or events.
3. Fix the deployment so Pods run successfully.
4. Confirm all Pods are Running and stable.

## Rules

- Use `--context AIOps-Agent-Benchmark` on every kubectl command.
- Read logs and events **before** making any changes.
- Do not delete and recreate the Deployment: patch or edit it.
- Do not modify anything outside the `staging` namespace.
