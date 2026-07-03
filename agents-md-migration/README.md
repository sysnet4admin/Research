# AGENTS.md Migration

[한국어](README_ko.md)

Does moving a project context file from `CLAUDE.md` to **AGENTS.md** make Claude Code slower or more expensive?

That question is where this study started.

[AGENTS.md](https://agents.md/) is the open context-file format governed by AAIF (Agentic AI Foundation, Linux Foundation), read by 30+ coding agents. Claude Code does not read it natively ([issue #34235](https://github.com/anthropics/claude-code/issues/34235)), so a migration needs one of two workarounds: an `@AGENTS.md` import line inside `CLAUDE.md`, or a `CLAUDE.md` symlink pointing at `AGENTS.md`. This study measures whether either workaround costs anything, on real Kubernetes incident-response tasks.

> **This README is a reference sheet for results, environment, and reproduction.** Motivation and interpretation live in the [blog post](https://kuberneteslab.dev/en/blog/agents-md-migration/).
>
> Scenarios, scoring parser, and audit capture are reused from the companion [AIOps Agent Benchmark](https://github.com/sysnet4admin/Research/tree/main/AIOps-Agent-Benchmark). This study runs Claude Code only; it is not a cross-vendor comparison.

## TL;DR

- **All three delivery methods load.** A canary check confirmed Claude Code follows both the `@AGENTS.md` import and the symlink (a no-context control did not respond to the canary).
- **No systematic slowdown.** Across 5 model configurations (Haiku 4.5, Sonnet 4.6, Sonnet 5, Opus 4.8, Fable 5), wall-time deltas flip sign between conditions and do not track token deltas, which is the signature of LLM run-to-run variance, not context-loading overhead.
- **No token-cost penalty.** Cache-write token deltas between conditions stay within ±6% and move together with the symlink condition, which is mechanically identical to native and therefore acts as a built-in control. On four models the import measured 3 to 4% lower than native; on Sonnet 5 both the import and the symlink measured 6% higher, which marks that delta as run-to-run noise rather than a delivery cost.

## Conditions

The payload (context body) is byte-identical across conditions, verified by checksum. Only the delivery mechanism differs.

| Condition | Files in the agent working directory | How Claude Code loads it |
|---|---|---|
| **A** native | `CLAUDE.md` (body) | reads `CLAUDE.md` directly |
| **B** import | `CLAUDE.md` (single line `@AGENTS.md`) + `AGENTS.md` (body) | follows the `@AGENTS.md` import |
| **C** symlink | `AGENTS.md` (body) + `CLAUDE.md` symlink to it | opening the `CLAUDE.md` path makes the OS resolve the link and return the `AGENTS.md` content |

In condition C, Claude Code does nothing special: the filesystem resolves the link at open time, so from Claude Code's side the read is identical to native. That also makes C a built-in control group: any delta C shows against A is measurement noise, so B only carries a real indirection cost if it exceeds what C shows.

The payload is a real, human-curated context file (the AIOps benchmark's project `CLAUDE.md`: cluster rules, scoring formulas, known pitfalls), not a synthetic document.

## Results

### Cost: cache-write tokens

If the import or symlink inflated what gets loaded, condition B would show more cache-write tokens than the control C. Median per condition (n = 12 per cell: 4 scenarios x 3 repetitions):

| Model | A (native) | B (import) vs A | C (symlink, control) vs A |
|---|---|---|---|
| Haiku 4.5 | 22,049 | -3% | +1% |
| Sonnet 4.6 | 14,357 | -3% | -1% |
| Sonnet 5 | 17,252 | +6% | +6% |
| Opus 4.8 | 15,542 | -4% | -1% |
| Fable 5 | 16,357 | -3% | -1% |

No row shows B systematically above the control. On four models the import measured 3 to 4% lower than native; on Sonnet 5 it measured 6% higher, but the symlink control moved by the same +6% in the same runs, and a symlink cannot mechanically differ from native. So the Sonnet 5 delta is run-to-run noise (its output tokens also rose about 20% in those conditions), not an indirection cost.

Two caveats about this metric surfaced in the data. Cache-write totals accumulate across turns, so longer solution paths write more cache. And adjacent runs with an identical assembled context can hit the server-side prompt cache within its TTL, sharply reducing the write (observed once). The per-run cluster snapshot guarantees a cold start at the cluster level, not at the API cache level.

### Speed: wall time

Median wall time per condition (seconds):

| Model | A | B | C |
|---|---|---|---|
| Haiku 4.5 | 22.1 | 22.8 | 29.8 |
| Sonnet 4.6 | 40.1 | 51.9 | 37.6 |
| Sonnet 5 | 49.7 | 53.7 | 47.8 |
| Opus 4.8 | 76.2 | 69.1 | 89.3 |
| Fable 5 | 79.2 | 90.6 | 76.5 |

Deltas are large but unsystematic: the sign flips between models and conditions, and the biggest time deltas come with near-zero token deltas (for example Haiku C: +35% time, +3% tokens). A delivery-method overhead would produce a consistent sign; this pattern is agent trajectory variance.

Output tokens and tool-call counts are also flat (within ±15% and ±8%, mixed signs).

## Method

- **Tasks**: Kubernetes incident-response scenarios from the AIOps Agent Benchmark (broken deployment, wrong service selector, OOM limit, failing readiness probe). Each run: restore cluster snapshot, inject the fault, run the agent with `--dangerously-skip-permissions`, cold start.
- **Isolation**: the agent runs in a fresh temp working directory containing only the condition's context files, on a dedicated 2-node cluster (not shared with other benchmarks). Every kubectl command pins `--context agents-md-migration`.
- **Fairness**: condition order is shuffled per scenario so time-of-day drift cannot pile onto one condition. The user-level `~/.claude/CLAUDE.md` is identical for all conditions, so it cancels out.
- **Load verification first**: before measuring speed, a canary line in the payload ("reply PONG-AGENTSMD to PING") confirmed each condition actually loads. All three responded; the empty-directory control did not.
- **Volume**: a 10-scenario pass across A/B/C (30 runs, Sonnet 5), then a model sweep on the 4 low-variance scenarios x A/B/C x 5 models x 3 repetitions (180 runs). All 210 published runs completed rc=0; one run hit a transient API 500 server error and was re-run under the infrastructure-failure policy.

## Environment

| Item | Value |
|---|---|
| Claude Code | 2.1.198 (4-model sweep), 2.1.199 (Sonnet 5 runs), load check on 2.1.195 |
| Models | claude-haiku-4-5, claude-sonnet-4-6, claude-sonnet-5, claude-opus-4-8, claude-fable-5 |
| Kubernetes | v1.36.2 (kubeadm), containerd 2.2.3, Ubuntu 24.04 |
| Cluster | 1 control-plane + 1 worker, Vagrant + VirtualBox, Calico CNI, MetalLB |
| Measured | 2026-07-02 to 2026-07-04 |

| Node | Role | IP |
|---|---|---|
| cp-k8s | control-plane | 192.168.2.10 |
| w1-k8s | worker | 192.168.2.11 |

## Reproduce

```bash
# 1) cluster
cd test-cluster && ./up.sh && ./snapshot.sh    # baseline snapshot

# 2) one run: condition x scenario x repetition tag
cd ../studies/agents-md-import-speed
./run_one.sh B 001-crashloop r1

# 3) full pass and model sweep
./run_suite.sh r1
REPS=3 bash run_model_sweep.sh

# 4) aggregate
python3 report_sweep.py   # model x condition medians
python3 aggregate.py      # per-run CSV
```

Per-run raw data (`runs/`) and the measured payload (a working project `CLAUDE.md` that contains private operational notes) stay in the private workspace; this repository publishes the harness scripts and the aggregated results. Any byte-identical payload placed in the three `variants/` layouts reproduces the comparison, since only the delivery mechanism differs. The aggregation scripts (`aggregate.py`, `report_sweep.py`) import the AIOps benchmark's parser, which is not published; treat them as method documentation.

## Limitations

- Accuracy and safety scoring (Ops_Score, deterministic audit-based unsafe-action count) were not part of this pass; the study answers the speed and token-cost question. The audit slices are captured per run, so that scoring can be added later.
- The model sweep covers the 4 low-variance scenarios; the harder scenarios (multi-step root-cause chains) ran once per condition and are dominated by trajectory variance, which is exactly why the sweep was scoped to the low-variance set.

## Prior work

- [arXiv 2601.20404](https://arxiv.org/abs/2601.20404) measured human-written AGENTS.md files with Codex (native AGENTS.md reader): median runtime -28.6%, output tokens -16.6%. It did not measure the import indirection or a non-native reader, which is the gap this study fills for Claude Code.
- An [ETH Zurich study (arXiv 2602.11988)](https://arxiv.org/abs/2602.11988) found LLM-generated AGENTS.md files *reduced* success and raised cost, so how the file is written decides the outcome. This study holds the file fixed (human-curated) and varies only the delivery method.
