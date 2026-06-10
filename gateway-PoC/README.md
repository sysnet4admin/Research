# Kubernetes Gateway API PoC

[한국어](README_ko.md)

A live-cluster benchmark comparing 7 Gateway API implementations, built for teams migrating from Ingress (ingress-nginx) to the Kubernetes Gateway API.

## Two ways to read this benchmark

The same measurement (7 implementations on a live cluster, Gateway API v1.4) is presented through two lenses. Pick the one that matches your question.

| View | Your question | Where |
|---|---|---|
| **Starting point (migration)** | "I run ingress-nginx. What carries over, and what breaks, if I move to each implementation?" | [`metrics/migration-view/`](metrics/migration-view/) |
| **Rigor (conformance)** | "How faithfully does each implementation realize the Gateway API spec, and how well does it behave under measurement?" | [`metrics/conformance-view/`](metrics/conformance-view/) |

What makes this different from official material: unlike the Gateway API conformance suite (self-declared PASS/FAIL) and ingress2gateway (mechanical annotation conversion), this benchmark measures live behavior, includes the vendor-extension features that conformance leaves out of scope (rate limiting, auth, body size), and compares the feature-breadth spread *within* conformant implementations.

Each view has a short intro (`README.md`), the full tables rendered on GitHub (`README_tables.md`), and an interactive version (`report.html`).

## What is measured

- **7 implementations**, Gateway API v1.4 (experimental channel CRDs, a superset of standard):

  | Implementation | Version | Implementation | Version |
  |---|---|---|---|
  | NGINX Gateway Fabric | 2.4.2 | Kong (KGO) | 2.1 |
  | Envoy Gateway | v1.7.3 | kgateway | v2.2.2 |
  | Istio | 1.30.0 | Traefik | v3.6.17 |
  | Cilium | 1.19.4 | | |

- **Graded conformance**: Core (7) + Extended standard channel (13) + Extended experimental channel (1), scored from live data-path measurement aligned to the official model (deterministic items over 3 rounds; weighted-routing canary over a frozen 155-round pool).
- **Beyond conformance**: vendor-extension matrix (rate-limiting, body-size, regex, tls-passthrough, ip-filter, basic-auth), non-functional and operational metrics (load, failover-recovery, health-check, config-robustness), and an auth cross-section (JWT, external-auth).
- **Migration evidence**: ingress2gateway 1.1.0 run per ingress-nginx annotation, with before/after manifests and conversion notices preserved under [`migration/i2gw/`](migration/i2gw/).

The headline: **all 7 are Core conformant**. What separates them is Extended feature breadth (6 to 13 of 13) and the vendor extensions that conformance does not score. The two views above carry the measured tables.

## Repository layout

| Path | Contents |
|---|---|
| [`metrics/`](metrics/) | The two reports (migration-view, conformance-view) |
| [`scripts/`](scripts/) | Scoring pipeline (aggregate, score, report) and `finalize.sh` |
| [`measurement/`](measurement/) | Test harness (per-round run, test library, fixtures) |
| [`implementations/`](implementations/) | Per-implementation install scripts (7) |
| [`migration/i2gw/`](migration/i2gw/) | ingress2gateway conversion evidence |
| [`results/`](results/) | Raw measurement rounds and aggregates |
| `SCORING.md`, `rubric.yaml` | Scoring model and frozen rubric (v3) |

## Reproduce

The full pipeline (aggregate, score, render both views) runs from one entry point:

```bash
./scripts/finalize.sh
```

Measurement harness and per-implementation install scripts live under `measurement/` and `implementations/`. The scoring model and the freeze procedure are documented in `SCORING.md`.

## Earlier PoC (v1.2)

The first iteration of this PoC (17 tests, Gateway API v1.2, 100 rounds) is archived on the [`gateway/v1.2`](https://github.com/sysnet4admin/Research/tree/gateway/v1.2) branch. The current results on this branch are the re-measured Gateway API v1.4 benchmark (two channels, vendor extensions, operational metrics).

## References

- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway)
- [NGINX Gateway Fabric](https://github.com/nginxinc/nginx-gateway-fabric) / [Envoy Gateway](https://gateway.envoyproxy.io/) / [Istio](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) / [Cilium](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/) / [Kong](https://docs.konghq.com/gateway-operator/latest/) / [Traefik](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/) / [kgateway](https://kgateway.io/)
