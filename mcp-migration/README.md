# What actually changes when you migrate an MCP server to the stateless spec?

[한국어](README_ko.md)

> **This README is the reference for numbers, conditions, and reproduction.**
> The step-by-step migration walkthrough with verbatim payloads is in the
> [blog post](https://kuberneteslab.dev/en/blog/mcp-stateless-migration/).

The MCP 2026-07-28 revision is the protocol's largest change since launch:
protocol-level sessions and the `Mcp-Session-Id` header are gone, every request
carries what it needs, and anything that used to live in a session now travels
as an explicit handle in ordinary tool arguments. Plenty of writeups explain
what changed. What we could not find is a measurement: how much does this
actually matter when the server runs on Kubernetes, behind a load balancer,
with replicas scaling and pods being replaced?

So we measured it. The same workload runs twice: once on an old-spec
(2025-11-25) session-based server, once ported to the new stateless spec, on
the same cluster, driven by the same load generator, on the release-week
stable SDK. After the main run we widened the sample, so the scale-out cells
below carry 10 to 22 observations each. This repository holds the harness,
the ported server, and the numbers.

Terms used throughout: rps is requests per second (offered = what the load
generator attempts, achieved = what actually succeeded). A session loss is a
request rejected because the server does not recognize the session it belongs
to (HTTP 400/404 on the old spec). A handle loss is a tool-level error on the
new spec when a handle points at state the receiving pod does not have.

## Summary

- On the old spec, adding replicas makes things worse, not better. At 200 rps
  offered, going from 1 to 4 replicas drops the median achieved throughput
  from 199.9 to 33.2 rps, with 37,844 session losses out of 78,000 requests.
  And repeating the same cell lands anywhere from 22.4 to 57.0 rps, run to
  run.
- The new spec held a median 200.0 rps across all 69 observations, at every
  replica count and in both connection modes, with the lowest run at 199.7.
  Losses were zero in every one of the 69.
- Killing a pod mid-run cost the old spec 1,922 session losses over six runs
  (59 to 1,072 per run); the new spec lost nothing in any of its three.
- Migrating the transport does not migrate the application. Port to the
  stateless spec but keep handle state in pod memory and the old pathology
  comes back: half the offered rate under scale-out, and 13,942 handle losses
  across five pod-replacement runs. Self-contained handles (HMAC-signed) and
  external storage (Redis) ran clean through both.
- If you cannot migrate yet, two bridges actually work. Turning on the
  Service's session affinity (`sessionAffinity: ClientIP`) removes the losses
  but pins all traffic from one client IP to one pod; a gateway (agentgateway
  v1.4.1) absorbs both scale-out and pod replacement, at the price of moving
  the session-keeping burden into the gateway itself.
- The blocker we hit in the pilot is fixed: agentgateway v1.4.0-alpha.1
  corrupted `params._meta`, breaking new-spec passthrough; v1.4.1 passes it
  intact.

## Should you migrate, and what to watch

| Situation | What the numbers say |
|---|---|
| You scale out, autoscale, or deploy often | Migrate. The old spec loses sessions on every replica change and every pod replacement, and its throughput varies run to run. The new spec held the offered rate in every condition we measured |
| You are porting now | The handle design is the decision that matters. Keep state out of pod memory: sign it into the handle (HMAC) or put it in external storage. Both ran clean through scale-out and pod replacement; pod memory lost requests in both |
| You cannot migrate yet | Sticky sessions and gateway session routing both work, with different costs. Session affinity gives up load balancing; a gateway moves the session-keeping burden into the gateway layer |
| You run clients | Nothing to do per-request: the new dialect is headers plus `_meta`, and the release-week SDKs fill the new required fields (`resultType`, `serverInfo`) automatically |

## What was measured

Two servers, one variable: the protocol era.

- **A (old spec, 2025-11-25)**: the official `server-everything` 2026.7.4,
  streamable HTTP, sessions in an in-memory Map. This is the migration
  starting point most session-based servers are in.
- **B (new spec, 2026-07-28)**: the same workload subset (echo, get-sum,
  counters) ported to the Python SDK `mcp` 2.0.0 stable. Because the spec
  leaves handle persistence to the application, B implements it three ways:
  pod-memory (the naive port), self-contained HMAC-signed handles, and
  Redis-backed handles.

Three measurements; one combination of conditions is called a cell below.
Three client-to-server paths were considered: (a) direct through the
LoadBalancer Service, (b) through a Gateway API implementation, (c) through
agentgateway. Paths (a) and (c) were measured.

- **M1 scale-out**: replicas 1 -> 2 -> 4 on path (a), 200 rps offered for
  30s, with both connection modes (a new connection per call, and connection
  reuse) because kube-proxy balances per connection.
- **M2 handle designs**: the three B variants at 100 rps.
- **M3 pod replacement**: kill one pod at the 20s mark of a 60s run.
- **Path (c) gateway**: the same workload through agentgateway v1.4.1, old
  spec with `sessionRouting: Stateful`, new spec with `Stateless`.

After the main run (2026-08-06) we continued with follow-up measurement: M1
repetitions raised to 10 to 22 per cell, old-spec pod replacement extended to
six runs (three for the new spec), plus session affinity, kube-proxy nftables
mode, client concurrency 4 to 32 (old spec), a 30-minute continuous run, pod
replacement per handle design, and a Redis outage, all on the same harness.

## Environment

- Kubernetes 1.36.2 (kubeadm), 3 nodes (1 control plane + 2 workers, 2 CPU /
  4GB each), VirtualBox arm64, Calico, MetalLB, kube-proxy in iptables mode
  (the default).
- The load generator runs on the host, not in a pod, so the measuring tool
  never competes with the measured workload. It speaks both dialects: the old
  handshake/session/reinitialize flow and the new headers-plus-`_meta` flow.
  No MCP-specific load tool existed, so this dual-dialect generator is part of
  the contribution.
- Versions are stamped into every run directory. Pilot numbers (measured on
  RC/beta SDKs in July) are kept internal; everything published here comes
  from the spec-final, stable-SDK runs.

## Results

![Scale-out: what gets through at 200 rps offered](studies/stateless-scaleout/assets/scaleout.svg)

| Cell | achieved rps, median (range) | p50 ms | session losses | handle losses |
|---|---|---|---|---|
| A old spec, new conn per call, replicas 1 | 199.9 (196.8 to 200.0) | 7.4 | 0 | 0 |
| A old spec, new conn per call, replicas 2 | 116.5 (91.9 to 155.1) | 6.7 | 22,220 | 0 |
| A old spec, new conn per call, replicas 4 | 33.2 (22.4 to 57.0) | 5.9 | 37,844 | 0 |
| A old spec, conn reuse, replicas 1 | 200.0 (102.5 to 200.0) | 4.9 | 16 | 0 |
| A old spec, conn reuse, replicas 2 | 168.9 (135.7 to 193.4) | 3.7 | 11,478 | 0 |
| A old spec, conn reuse, replicas 4 | 130.8 (95.6 to 190.6) | 2.8 | 40,773 | 0 |
| **B new spec, both modes x replicas 1/2/4** | **200.0 (199.7 to 200.0)** | 6.2 | **0** | 0 |
| B handle in pod memory, 100 rps | 51.2 | 6.7 | 0 | **4,461** |
| B handle self-contained (HMAC), 100 rps | 100.0 | 7.5 | 0 | 0 |
| B handle in Redis, 100 rps | 100.0 | 7.9 | 0 | 0 |
| A pod killed mid-run, 100 rps | 97.7 | 4.2 | **1,922** | 0 |
| B pod killed mid-run, 100 rps | 100.0 | 6.9 | **0** | 0 |
| A through gateway (Stateful), replicas 4 | 200.0 | 6.2 | 0 | 0 |
| B through gateway (Stateless), replicas 4 | 200.0 | 6.5 | 0 | 0 |

Throughput is the median of the repetitions with the observed range in
parentheses; losses are summed across them. Observation counts differ per
cell: M1 cells have 10 to 22 runs (78,000 requests for a 13-run cell); handle
cells have 3 runs (9,000 requests); pod kills have 6 runs for the old spec
(36,000 requests) and 3 for the new (18,000); gateway cells have 3. Rows with
6 runs or fewer omit the range. Every pod kill was verified to have actually
landed.

Old-spec cells above one replica vary considerably between runs, because the
outcome depends on which pods hold the sessions and which pods the
connections reach. Replicas 1 stays at 196.8 to 200.0 and the new spec's median is 200.0 with a
low of 199.7 across 69 observations, so the spread is a property of the old
spec, not measurement noise.

![Three handle designs under the stateless spec](studies/stateless-scaleout/assets/handles.svg)

## Before you read the numbers

- **Absolute throughput is not the point.** This is a small virtualized
  cluster and 200 rps is deliberately below saturation: pushing the new spec
  harder, it tracked the target exactly to 300 rps and fell behind from 400
  (324.6 achieved), still with zero losses. So the offered rate is about two
  thirds of what this cluster can serve, and what transfers is the shape:
  which configurations lose requests and which hold the offered rate.
- **Back-to-back connection-heavy cells need a cooldown.** Our first full run
  was invalidated by this: firing 200 new connections per second in
  consecutive cells piles up conntrack TIME_WAIT state (120s timeout) on the
  path, and later cells see p99 jump from 16ms to over 1s with throughput
  dropping. The runner now sleeps 180s between cells; the first run is kept
  in the repo history as the diagnosis record.
- **Behind a gateway, failure wears a different face.** On the direct path a
  lost session comes back as HTTP 400; through the gateway it comes back as a
  5xx. A client that only counts 400/404 will report the gateway as
  loss-free, and a client that does not re-initialize on 5xx will fail for
  the rest of the run and make the gateway look far worse than it is. Our
  harness started as the latter; that run was discarded and remeasured after
  teaching it to re-initialize on 5xx as well.
- **Gateway cells are not comparable to direct-path cells in absolute
  throughput.** The gateway control plane and proxy consume worker CPU, so
  scale-out cells run one server at 4 replicas at a time. Only the
  pod-replacement comparison ran gateway and direct back to back under the
  same conditions (2 replicas, 100 rps).

## Findings

### 1. On the old spec, scale-out subtracts capacity, and the result varies run to run

kube-proxy distributes per connection, and on the old spec a session lives in
one pod's memory. With a new connection per call, every added replica raises
the chance a request lands on a pod that has never seen its session. The loss
rate tracks the arithmetic: with N replicas a new connection misses the
session pod with probability (N-1)/N, and probing fresh sessions 60 times per
replica count showed first-connection losses at 50% for 2 replicas (theory
50%) and 82% for 4 (theory 75%).

Throughput falls further than the loss rate alone would suggest, because each
loss triggers a re-initialize that ties up a worker, and requests that cannot
be sent in the meantime are shed. That is why the 4-replica median is 33.2
rps, below the naive one-quarter of 200. Connection reuse softens this
(median 130.8) but cannot remove it: reconnects still happen, and every
reconnect re-rolls which pod the client is pinned to.

There is also a property you only see by repeating the runs: the same cell
lands anywhere from 22.4 to 57.0 rps over 13 runs, and 95.6 to 190.6 over 22
runs with connection reuse. Single-replica runs stay at 196.8 to 200.0, so
this is not measurement noise; it is the old spec's dependence on where
sessions happen to sit. Old-spec scale-out is not just slower, it is hard to
predict. The degradation also held across client concurrency 4 to 32, so it
is not an artifact of one client shape.

### 2. The new spec holds the offered rate in every condition

Same cluster, same load, replicas 1, 2, and 4 in both connection modes: the
median across all 69 runs is 200.0 rps with the lowest at 199.7, zero losses
in every run, and p50 steady at 6.2ms. There is
no session for a request to miss, so any pod can serve any request. This is
the entire architectural argument for the stateless revision, visible in one
row of numbers.

The result held as we changed the conditions: kube-proxy switched to nftables
mode and a 30-minute continuous run both produced zero server-side losses. The nftables comparison also confirms that
the old spec's session loss comes from per-connection balancing itself, not
from the dataplane implementation.

### 3. Pod replacement is only an event on the old spec

We killed a pod during a 60-second run six times against the old spec and
three times against the new. The old spec lost 1,922 requests to session
loss, ranging from 59 to 1,072 per run depending on how many sessions the
killed pod happened to hold. The new spec went through its three kills
without losing a request. Rollouts, node drains, and autoscaler scale-in do this to
pods constantly, which is why the difference matters outside of benchmarks.

The same test applied to the handle designs: the pod-memory variant lost
13,942 handles across five kills, because a dying pod takes all of its state
with it, while HMAC and Redis lost none. We also killed Redis itself mid-run:
91.7 rps achieved with 24 losses, small because the pod restarts quickly, but
a reminder that external storage is a dependency you now have to keep alive.

### 4. The handle design is where migrations succeed or fail

The spec deliberately leaves handle persistence to the application. Port your
server and keep handle state in pod memory, and the numbers look like the old
spec again: 51.2 of 100 rps achieved, 4,461 handle losses. Sign the state
into the handle itself (HMAC) or move it to Redis, and both run at the full
100 rps with zero losses at nearly identical latency (7.5 vs 7.9ms p50). The
pod-replacement runs above split exactly the same way. A stateless transport
does not make a stateless application; that part of the migration is yours.

### 5. Both bridges for the old spec work, at different costs

If you have to run an old-spec server at multiple replicas before migrating,
there are two options, and both removed the losses in our runs.

One is the Service's sticky sessions. With `sessionAffinity: ClientIP`, four
replicas served 200.0 rps with zero losses (26.4 rps median and 13,760 losses
without it), and pod-replacement losses fell from 2,148 to 88. One caveat:
our load generator is a single host, so a single client IP, and ClientIP
affinity pins per IP; all traffic went to one pod. Perfect session survival
was bought with zero load balancing. Real fleets have many client IPs, so the
effect will be partial.

The other is a session-terminating gateway. With agentgateway v1.4.1 and
`sessionRouting: Stateful`, scale-out at 4 replicas ran loss-free, and pod
replacement ended with 20 failures across five runs, 4 per run; the same-day
direct-path control lost 1,255 across three runs, 418 per run. The gateway
terminates the session and re-pins it to a surviving pod. Note that these
numbers come from a client that re-initializes on 5xx: behind the gateway a
lost session surfaces as a 5xx rather than a 400, and a client that does not
recover from 5xx would fare much worse.

Either way, the burden of keeping session state does not disappear; it moves.
Sticky sessions trade it against load balancing; a gateway carries it into
the gateway layer, which makes the gateway's own failure and replacement the
next thing to think about. We did not kill the gateway in this study. The new
spec posts the same numbers with neither device.

### 6. The ecosystem caught up during the release window

In the July pilot, agentgateway v1.4.0-alpha.1 mangled `params._meta`, so
new-spec traffic could not pass through it end to end. v1.4.1 (released right
after the spec) passes it intact, and both SDKs shipped stable 2.0.0.
Against the release-final spec we also confirmed the changes that could have
affected this harness (error-code renumbering, required `resultType`,
`ttlMs`/`cacheScope` on list results) are all filled by the SDK; a server
ported on the beta SDK ran unmodified on stable.

## Limits

- Small virtualized cluster; absolute throughput and latency do not
  extrapolate. Relative shapes are the result.
- One workload family (small JSON tool calls). Large payloads, streaming, and
  `subscriptions/listen` are not covered.
- Path (b), a Gateway API implementation between client and server, was not
  measured. Path (c) covers the gateway question with agentgateway only.
- Old-spec medians are locations, not guarantees: even at 13 to 22 runs the
  observed ranges stay a factor of two wide.
- The session-affinity result is from a single client IP (see finding 5).
- The gateway's own failure and redundancy were not measured.

## Reproducing

```
test-cluster/                     Vagrant 3-node cluster, baseline snapshot
studies/stateless-scaleout/
  b-server/                       new-spec port (3 handle designs)
  images/                         image build + load into containerd
  k8s/                            deployments, services, agentgateway path
  harness/loadgen.py              dual-dialect load generator
  harness/capture.py              verbatim before/after payload capture
  harness/run_main.sh             direct-path campaign (M1/M2/M3)
  harness/run_gateway.sh          gateway-path campaign
  harness/verify_repro.sh         rebuilds from scratch in the documented order
  harness/chart.py                charts from run data
```

Run order matters: start the cluster, restore the baseline snapshot, then
build and load images, then deploy (the snapshot restore would wipe images
loaded before it). The image build also needs a running Docker daemon; on
machines where the daemon is started by hand (colima and the like) the build
script now checks first, tries to start it, and stops with a clear error
otherwise. We lost an unattended run to that assumption before adding the
check. Aggregated tables are in this README; per-cell JSON stays out of git
and is available on request.
