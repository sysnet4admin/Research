# Scenario 011 — Pod Repeatedly Evicted

## Context

You are an SRE. The `log-writer` pod in the `logging` namespace
keeps getting evicted and restarting. The pod has been cycling for
the past 5 minutes. Memory appears normal.

Cluster context: `AIOps-Agent-Benchmark`

## Task

1. Investigate why `log-writer` keeps getting evicted.
2. Determine the exact eviction reason — do not assume it is memory.
3. Fix the deployment so the pod runs stably without eviction.
4. Confirm the pod stays Running for at least 2 minutes.

## Rules

- Use `--context AIOps-Agent-Benchmark` on every kubectl command.
- Check all resource dimensions, not just memory and CPU.
- Do not modify anything outside the `logging` namespace.
- Do not delete and recreate the Deployment.
