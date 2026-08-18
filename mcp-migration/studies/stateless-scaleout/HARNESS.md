# MCP stateless benchmark harness

A load generator and measurement harness for comparing the MCP 2025-11-25
(session) and 2026-07-28 (stateless) specs on Kubernetes. No MCP-specific load
tool existed when this study started, so the generator speaks both dialects
directly over HTTP rather than through an SDK. That is deliberate: counting
protocol-level failures (session loss, handle loss) requires seeing the raw
status codes and tool errors that an SDK would smooth over.

## What is here

```
harness/loadgen.py      Dual-dialect load generator (the core tool)
harness/capture.py      Records verbatim request/response pairs for documentation
harness/run_main.sh     Direct-path campaign: scale-out, handle designs, pod kill
harness/run_gateway.sh  Same cells through agentgateway
harness/chart.py        Charts and aggregate numbers from run data
b-server/server.py      New-spec server port, with three handle designs
examples/               Minimal client showing both dialects side by side
tests/                  Offline tests: dialect construction, aggregation rules
k8s/                    Deployments, services, gateway wiring
```

## Requirements

Python 3.11 or newer, `httpx`. A Kubernetes cluster is needed only for the
campaign scripts; the tests and the aggregation run offline.

```sh
uv venv --python 3.13 .venv && uv pip install --python .venv/bin/python httpx pytest
```

## Deploy the two servers

`deploy.sh` does the whole setup: namespace, the ConfigMap that supplies
`b-server/server.py` to the new-spec pods, Redis, both Deployments and Services,
and it waits for the rollouts. Build and side-load the images first, because
`imagePullPolicy: Never` means there is no registry to fall back to.

```sh
docker info > /dev/null             # the daemon must be up; the build script checks too
./images/build_and_load.sh          # builds a-server and b-server, imports into containerd
./k8s/deploy.sh                     # namespace, configmap, redis, both servers
```

`build_and_load.sh` now refuses to run without a Docker daemon and tries to start
colima once before giving up (set `AUTO_START_COLIMA=0` to skip that). This is not
theoretical: an unattended reproduction run in August restored the snapshot, failed
the build because colima was down, deployed anyway, and left the new-spec pods on
`ErrImageNeverPull` for the rest of the night.

## Run the tests first

They check that each dialect is constructed the way its spec requires, and that
the aggregation rules behind the published tables (median of repetitions for
throughput, sum for losses) still hold. If run data is present they recompute
the published numbers from it.

```sh
.venv/bin/python -m pytest tests/ -q
```

## Try one call in each dialect

Against a deployed pair of servers, this is the whole difference in two
functions: the old spec spends two round trips on a handshake and then depends
on the session header, the new spec sends one self-describing request.

```sh
.venv/bin/python examples/minimal_client.py old http://<A_LB_IP>/mcp
.venv/bin/python examples/minimal_client.py new http://<B_LB_IP>/mcp
```

## Generate a load

`loadgen.py` drives an open loop at a fixed rate: ticks are issued on schedule
and workers consume them, so a slow server shows up as achieved falling below
offered rather than as back-pressure on the generator. It reports achieved
throughput, latency percentiles, and protocol-level failures as JSON.

```sh
.venv/bin/python harness/loadgen.py \
  --url http://<LB_IP>/mcp --dialect b --tool echo \
  --concurrency 16 --duration 30 --conn-mode close --rps 200 \
  --out cell.json
```

Two options decide what you are actually measuring:

- `--dialect a|b` picks the protocol era. This is the study's only variable.
- `--conn-mode close|reuse` decides whether each call opens a new TCP
  connection. kube-proxy balances per connection, so `close` is what exposes
  the session-affinity problem. With `reuse` you stay pinned to one pod and the
  problem hides.

Tools: `echo` and `get-sum` are stateless and exist in both dialects.
`counter_mem`, `counter_hmac`, and `counter_redis` are new-spec only and
exercise the three handle designs.

## Run a campaign

`run_main.sh` runs the full direct-path matrix: scale-out at 1, 2, and 4
replicas in both connection modes, the three handle designs, and a pod kill
during a run. Each cell repeats three times.

```sh
./harness/run_main.sh http://<A_LB_IP>/mcp http://<B_LB_IP>/mcp \
  .venv/bin/python runs/$(date +%F) 3
```

**Leave the cooldown alone.** The runner sleeps `COOLDOWN` seconds (default 180)
between cells. Cells that open a connection per request at 200 rps leave
conntrack entries in TIME_WAIT with a 120-second timeout, and without the
cooldown later cells inherit them: p99 climbs from 16ms to over a second while
p50 barely moves, and throughput sags. The first full run of this study was
invalidated by exactly that.

## Record payloads for documentation

`capture.py` performs one scripted sequence in each dialect and writes both a
structured JSON file and a markdown rendering, with response headers filtered
to the ones that carry protocol meaning.

```sh
.venv/bin/python harness/capture.py http://<A_LB_IP>/mcp http://<B_LB_IP>/mcp payloads/
```

It reproduces a session loss and a handle loss on purpose, so both servers need
at least two replicas for it to capture anything interesting.

## Verify a from-scratch rebuild

`verify_repro.sh` runs the documented setup order and checks each step's exit code,
then confirms the pods are actually ready and that the documented examples work. Use
it after changing anything in the setup path.

```sh
./harness/verify_repro.sh http://<A_LB_IP>/mcp http://<B_LB_IP>/mcp .venv/bin/python out/
```

It exists because the first version of this check was inlined in a campaign script
without exit-code checking, so a failed image build passed silently and two later
campaigns ran against a half-deployed cluster.

## Order matters when setting up

Start the cluster, restore the baseline snapshot, then build and load images,
then deploy. Restoring the snapshot after loading images removes them, and with
`imagePullPolicy: Never` and no registry there is no fallback.

## Interpreting the output

Each cell writes one JSON file with `achieved_rps`, `latency_ms` percentiles,
`session_loss`, `handle_loss`, `reconnects`, and an `errors` breakdown. A
session loss is a request the server rejected because it did not recognize the
session (HTTP 400 or 404). A handle loss is a tool-level error where a handle
pointed at state the receiving pod did not hold; note that these return HTTP
200, so transport-level retries will not see them.

Absolute throughput depends on the cluster and is not the point. What transfers
between environments is the relative shape: which configurations lose requests
as replicas are added, and which stay flat.
