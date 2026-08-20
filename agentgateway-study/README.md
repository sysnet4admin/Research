# agentgateway-study: what the gateway actually enforces and observes for MCP

[한국어](README_ko.md)

This study measures the distance between what the agentgateway documentation
says and what the gateway actually enforces and observes when it fronts MCP
(Model Context Protocol) servers. Instead of reading feature tables, we
verified behavior: what CEL authorization policies block, what they silently
block by mistake, how far trace context travels, and what putting the gateway
in the path costs. It applies the "declared versus enforced" frame from
[gateway-PoC](../gateway-PoC) to an MCP gateway.

The target is agentgateway v1.4.1 in Kubernetes mode, with the new-spec
(2026-07-28) MCP server built in [mcp-migration](../mcp-migration) as the
backend.

## Findings

1. **A tool-name allowlist blocks calls and filters the list.** With a policy
   allowing only `echo`, calls to other tools are rejected with 400 and the
   tools disappear from `tools/list`. The rejection is not an authorization
   error but `"Unknown tool"` (-32602): a deliberate design that makes blocked
   tools look nonexistent (anti-enumeration, discussed in upstream #758). The
   cost is that a client cannot tell "no permission" from "no such tool".
2. **A policy that conditions on tool arguments is accepted, then locks the
   whole backend.** This is the core finding. A rule like
   `mcp.tool.arguments.a == 1` passes validation (`Accepted`) and reports
   healthy status. But the authorization-time CEL context has no tool
   arguments, so the condition can never evaluate, and since
   `matchExpressions` is an allowlist, every call is rejected, including calls
   that satisfy the written condition. Under this rule `tools/list` returns an empty
   list, and the natural `has(...)` guard lifts the lockout but
   short-circuits for every call, silently degrading the rule to name-only
   (`a=2`, which the rule meant to block, passes; measured). So there is no
   workaround for argument-level control: the operator believes it is in
   place, and what they actually have is a full outage or a vanished
   condition.
3. **Policies evaluate the original tool name, and renaming is not a
   bypass.** Across all three prefixMode settings, no renamed (prefixed) name such as
   `mcp-b-80_echo` slipped past a block. Two traps instead: writing the policy against the renamed
   name that clients actually see in `tools/list` produces the same total
   lockout as finding 2, and a name the policy allows reaches the server even
   if the tool does not exist there, failing as 200 + isError rather than the
   gateway's 400.
4. **Rule count does not affect latency at this scale.** With 0, 1, and 21
   rules, median p50 stayed within 5.8 to 7.2 ms and every run held the
   offered rate.
5. **traceparent crosses the gateway and lands in `_meta` too.** The
   downstream server receives a traceparent header with the client's trace-id
   preserved and the gateway's own span-id, and the same value injected into
   `params._meta.traceparent`, the spot the MCP spec reserves (5 out of 5
   probes). None of this is documented. We measured with gateway tracing not
   configured; the span-parenting defect in the tracing-enabled path was
   reported upstream as #2904, and the merged fix lands in a release after
   the measured v1.4.1.
6. **The gateway costs about 1 ms at p50, and tail latency actually
   improved.** Comparing the direct path against the gateway path under
   identical resource conditions, p50 rose by 0.5 to 0.8 ms while median p99
   was lower through the gateway (table below). Both paths held the offered
   rate with zero errors.

## What an operator writing policies should know

| Intent | Works? | Caveat |
|---|---|---|
| Tool-name allowlist | Yes | List filtering comes with it. Rejection is 400 + "Unknown tool" (-32602), not an authorization error |
| Argument-based control ("block delete, but only for prod") | No | The config is accepted but the backend locks up entirely. A `has(...)` guard lifts the lockout but silently drops the condition (name-only). Argument-level control needs a separate external processor (mcpGuardrails, a gRPC server you build) |
| Policies under renaming (prefixMode) | Yes | Always write the original name. Using the prefixed name clients see locks everything out |
| Adding rules and worrying about latency | No need | No difference up to 21 rules |
| Distributed tracing | Yes | Propagated in both the header and `_meta` (verified with tracing not configured) |

## Numbers

Environment: 3-node VirtualBox Kubernetes v1.36.2 (MacBook Pro M4 Pro),
agentgateway v1.4.1, backend at 1 replica, echo tool, 30-second runs in close
mode (a new connection per call), cooldowns (60 s between rule-count repetitions, 180 s between A/B cells).
Absolute numbers are
from a virtual environment; read them comparatively.

Latency by rule count (median of 5 runs each):

| Rules | 100 rps p50 | 200 rps p50 |
|---|---|---|
| 0 | 7.2 ms | 5.8 ms |
| 1 | 6.9 ms | 6.4 ms |
| 21 | 6.9 ms | 6.3 ms |

Gateway versus direct (median of 5 runs each). The gateway control plane and
proxy stayed installed while both arms ran, so resource conditions were
identical and the only difference between arms was the load generator's
target address:

| Path | Offered rps | Achieved | p50 | p99 | Errors |
|---|---|---|---|---|---|
| direct | 100 | 100.0 | 6.6 ms | 21.6 ms | 0 |
| gateway | 100 | 100.0 | 7.1 ms | 17.9 ms | 0 |
| direct | 200 | 200.0 | 5.3 ms | 23.2 ms | 0 |
| gateway | 200 | 200.0 | 6.1 ms | 12.6 ms | 0 |

The lower p99 through the gateway likely comes from the gateway layer
absorbing the connection churn of close mode; we did not attribute it in
source.

## What was measured

- **Policy enforcement (P0 to P4)**: no-policy baseline, allowlist
  enforcement and list filtering, three probes against the argument-condition
  policy (condition true, condition false, unrelated tool), the full matrix
  of three prefixMode settings x two policy name forms x four call names, and
  rule count x offered rate x 5 repetitions. Follow-up probes covered
  `tools/list` under the argument rule and two `has(...)` guard variants.
- **Observability (T1/T2)**: a tap proxy behind the gateway recorded the
  exact traceparent header and `params._meta` the downstream server receives
  (5 probes).
- **Gateway versus direct (A/B)**: 20 cells against the same backend with
  only the target address changed.
- Two integrity notes. A mid-run process kill during the rule-count cells
  was resumed for the remaining 6 cells with the gateway and policy
  configuration kept identical. And the first verdict on trace propagation
  was a false negative caused by a probe-tool defect; after fixing the
  probe, the valid re-measurement reversed the verdict to "propagated".
  Both are recorded internally together with the raw data.

## Limits

- One backend with a small surface (8 tools). List-filtering cost on large
  tool sets was not measured.
- Alternative paths to argument-level control (extAuthz, extProc,
  mcpGuardrails and similar external processors) were not tested.
- Authentication (MCP Auth) and virtual LLM routing are out of scope.
- Absolute latency numbers are VirtualBox values.
- The tracing-enabled path (span export) was not measured.

## Reproduction

Run `harness/run_axes.sh` (policy and observability),
`harness/t1p3_addendum.sh` (follow-up), and `harness/run_ab.sh` (gateway
versus direct) in that order. Prerequisites are the cluster and new-spec
server deployment from [mcp-migration](../mcp-migration); gateway install and
removal reuse the scripts under its
`studies/stateless-scaleout/k8s/agentgateway/`. Each script removes
the gateway after measuring, returning the cluster to its original state.

## Related

- Vendor performance benchmark: the agentgateway blog's agentgateway versus
  LiteLLM comparison (2026-08-13) covers proxy throughput and resources, a
  different axis from this study. This study is not a competitive benchmark;
  it measures whether policy and observability behave as documented.
- Upstream issues: #758 (rejection-shape discussion), #2713 (name mismatch in
  the authorization context), #2904 (span-parenting defect in the
  tracing-enabled path, fix merged). Finding 2 was reported by this study as
  [#3092](https://github.com/agentgateway/agentgateway/issues/3092).
