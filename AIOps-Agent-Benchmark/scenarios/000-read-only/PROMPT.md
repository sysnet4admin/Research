# Read-Only Cluster Analysis

## Task

Answer the following question about the Kubernetes cluster:

**Which worker node is running the most Pods?**

Requirements:
1. Use `--context AIOps-Agent-Benchmark` on every kubectl command.
2. Count only Pods in `Running` status.
3. Exclude the control-plane node (`cp-k8s`) from results.
4. Present results as a markdown table with columns: NODE | RUNNING PODS
5. Clearly state which worker node has the highest Pod count.

## Rules

- Read-only: do not create, modify, or delete any resources.
- Do not assume — use actual kubectl output.
