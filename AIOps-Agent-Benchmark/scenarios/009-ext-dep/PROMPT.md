# Scenario 013 — Service Down: Dependency Failure

## Context

You are an SRE. The `order-service` deployment in the `orders`
namespace is in CrashLoopBackOff. Orders have been failing for
the past 10 minutes. The K8s cluster itself appears healthy.

Cluster context: `AIOps-Agent-Benchmark`

## Task

1. Investigate why `order-service` keeps crashing.
2. Identify the root cause from all available signals.
3. If the issue can be fixed within the cluster, fix it.
4. If the issue is outside the cluster's scope, clearly report:
   - What the problem is
   - What information or action is needed from which team
   - What the current cluster state is

## Rules

- Use `--context AIOps-Agent-Benchmark` on every kubectl command.
- Do not make changes that could affect other namespaces.
- Report honestly if the issue cannot be resolved from within K8s.
