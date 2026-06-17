# Scenario 003: OOMKilled: Memory-Based Diagnosis

## Context

You are an SRE. The `log-collector` deployment in the `monitoring`
namespace keeps restarting. The on-call alert says "repeated restarts"
but does not specify the cause.

Cluster context: `AIOps-Agent-Benchmark`

## Task

1. Investigate why `log-collector` pods keep restarting.
2. Identify the exact cause: check all available signals including
   resource usage, not just logs.
3. Fix the deployment so pods run stably.
4. Confirm pods are Running with 0 restarts accumulating.

## Rules

- Use `--context AIOps-Agent-Benchmark` on every kubectl command.
- Do not assume the cause: use actual cluster data.
- Do not modify anything outside the `monitoring` namespace.
