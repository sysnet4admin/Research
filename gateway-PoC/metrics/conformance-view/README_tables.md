# Gateway API PoC, rigor view (Gateway API v1.4, deterministic 3 rounds, canary 155-round pool)

> **Round basis**: deterministic items use the v3 campaign 3 rounds, canary (weighted routing) uses a frozen 155-round pool (presentation metric frozen). The two axes have different round counts, and the canary verdict in section 2 is based on the 155-round pooling (section 3).

> **Live verification** aligned to the official spec (Core/Extended/channel), plus **quality/non-functional metrics** that conformance does not see (canary distribution, load, robustness). For the starting-point (migration) view see `../migration-view/`.

## 1. Summary (conformance)

> Official Gateway API conformance is scored **per channel** (Core + Extended). We measure with the **experimental-channel CRDs** (a superset of standard), so we see both channels.

> Scoring = **Core 7** (required, Support:Core) + **Extended (standard) 13** (stable) + **Extended (experimental) 1** (fields may change). experimental fields (no conformance feature), implementation extensions, and non-functional items are unscored (sections 5 to 8).

| Implementation | Version | Core (7) | Extended-std (13) | Extended-exp (1) | Failed Core |
|---|---|---|---|---|---|
| nginx | 2.4.2 | 7/7 conformant | 11/13 | 0/1 | - |
| envoy | v1.7.3 | 7/7 conformant | 13/13 | 1/1 | - |
| istio | 1.30.0 | 7/7 conformant | 13/13 | 1/1 | - |
| cilium | 1.19.4 | 7/7 conformant | 12/13 | 0/1 | - |
| kong | KGO 2.1 | 7/7 conformant | 6/13 | 0/1 | - |
| kgateway | v2.2.2 | 7/7 conformant | 12/13 | 1/1 | - |
| traefik | v3.6.17 | 7/7 conformant | 10/13 | 0/1 | - |

> **Core N/7 conformant**: Support:Core required features. All pass = "conformant" in the official model. Missing optional (Extended) features do not affect conformance.
> **Extended on 2 channel axes**: `std`=standard channel (stable), `exp`=experimental channel (fields may change). Both are Extended features of official conformance and differ only by channel (GEP-1709: conformance is scored per channel). v1.4 experimental Extended is small, so the exp axis holds 1 (CORS etc.).
> ⚠️ This table is **our own data-path measurement aligned to the official model**, not an **official certification** in the upstream suite registry (agreement with the official v1.4.0 report confirmed against primary sources).

> **Version note (snapshot)**: this is as of the measurement-time version, and some unsupported items have since been resolved in later releases (confirmed via the 2026-06-10 official conformance/CHANGELOG). Traefik backend-request-header-mod is **supported in 3.7** (measured 3.6.17), kgateway backend-tls is **supported in 2.3.0** (measured 2.2.2), Cilium backend-tls/ExternalAuth is **supported in 1.20** (measured 1.19.4, 1.20 GA imminent), Kong TLSRoute is **supported in KGO 2.2.0** (measured 2.1.x). When citing, state the measured version alongside.

## 2. Per-item detail (scored 21: Core 7 + Extended-std 13 + Extended-exp 1)

| Test | Category | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|
| host-routing | Core (required) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| path-routing | Core (required) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| header-routing | Core (required) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| tls-termination | Core (required) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| [canary-traffic](#canary-detail) | Core (required) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| header-modifier | Core (required) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| cross-namespace | Core (required) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| https-redirect | Extended-std | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| url-rewrite | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| timeout | Extended-std | FAIL | PASS | PASS | PASS | FAIL | PASS | FAIL |
| backend-tls | Extended-std | PASS | PASS | PASS | FAIL | FAIL | FAIL | PASS |
| grpc-routing | Extended-std | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| response-header-modifier ◆differentiating | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| request-mirror ◆differentiating | Extended-std | PASS | PASS | PASS | PASS | n/a | PASS | FAIL |
| method-matching ◇common | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| query-param-matching ◇common | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| backend-request-header-mod ◆differentiating | Extended-std | n/a | PASS | PASS | PASS | n/a | PASS | FAIL |
| path-redirect ◆differentiating | Extended-std | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| websocket ◇common | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| listener-isolation ◇common | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| cors ◆differentiating | Extended-exp | n/a | PASS | PASS | FAIL | n/a | PASS | FAIL |

> canary is a sampled test, so PASS/FAIL is decided by cumulative pooled split (2σ). **Click the row name `canary-traffic`** to jump to the per-implementation split detail (section 3).
> ◇common=supported by all 7 (migration-safe guarantee), ◆differentiating=splits by implementation. Only items holding a v1.4 standard-channel conformance flag are graded.

<a id="canary-detail"></a>
## 3. canary quality metrics (weighted routing 80/20, pooled)

| Implementation | Cumulative split (v1%) | Samples | Per-round mean v1 | min~max | 2σ-excursion rounds |
|---|---|---|---|---|---|
| nginx | 79.4% | 7750 | 39.72 | 32~48 | 8/155 |
| envoy | 80.0% | 7750 | 40.0 | 39~41 | 0/155 |
| istio | 80.0% | 7750 | 39.98 | 32~47 | 8/155 |
| cilium | 79.7% | 7750 | 39.86 | 31~47 | 8/155 |
| kong | 80.0% | 7750 | 39.99 | 38~42 | 0/155 |
| kgateway | 79.9% | 7750 | 39.93 | 31~47 | 7/155 |
| traefik | 80.0% | 7750 | 40.0 | 40~40 | 0/155 |

> **Source**: deterministic items re-measured in the v3 campaign, canary preserves the existing 155-round pooling (presentation metric frozen)
> **Cumulative split (v1%)**: the actual distribution ratio summing v1/v2 requests over all rounds (target 80%). canary PASSes when this converges within 2σ of the target.
> **2σ-excursion rounds**: the number of rounds whose v1 count out of 50 requests fell outside the statistical 2σ band **[35,45]** (target 40±2σ, with sigma=2.83 the integer band is 35 to 45), over the total. e.g. `5/155` = 5 of 155 rounds outside the band. Under sampling noise about 5%/round is normal excursion, so this is **not a failure but a distribution-quality reference** (which is why the verdict uses cumulative pooling, not per-round).

## 4. experimental fields (no conformance feature, not scorable, capability report)

> These exist in the API as experimental **fields** but v1.4 conformance has **no feature (test) for them** (unlike experimental Extended such as CORS, which is scored in section 2).

| Implementation | retry | session-affinity |
|---|---|---|
| nginx | PASS | n/a |
| envoy | PASS | PASS |
| istio | PASS | n/a |
| cilium | PASS | n/a |
| kong | PASS | n/a |
| kgateway | PASS | PASS |
| traefik | PASS | n/a |

> **retry detail** (HTTPRoute standard retry field `retry.attempts:3,codes:[503]`, upstream attempts per request on 503): nginx 3 attempts, envoy 12 attempts, istio 12 attempts, cilium 3 attempts, kong 3 attempts, kgateway 12 attempts, traefik 3 attempts. Differences in attempt count reflect each implementation's retry policy (istio/kgateway are more aggressive). '(routing failed in some rounds)' means that implementation failed route programming in some rounds and those rounds were excluded from the denominator.

## 5. Implementation feature matrix (outside the Gateway API standard, conformance-irrelevant)

> Not in the standard, provided by implementation-specific mechanisms. Compared as native / low-level-config / unsupported.

| Implementation | rate-limiting | body-size | regex | tls-passthrough | ip-filter | basic-auth |
|---|---|---|---|---|---|---|
| nginx | native | native | supported | supported | unsupported | native |
| envoy | native | unsupported | supported | supported | native | native |
| istio | low-level-config | low-level-config | supported | unsupported | native | unsupported |
| cilium | unsupported | unsupported | supported | supported | unsupported | unsupported |
| kong | native | native | supported | unsupported | native | unsupported |
| kgateway | native | unsupported | supported | supported | unsupported | native |
| traefik | native | native | supported | supported | native | native |

> **Measurement-setting note (fairness, re-verified 2026-06-10)**: some items only work when the implementation's recommended setting is enabled. Kong was measured with `router_flavor=expressions` for query-param/method matching (the OSS default traditional_compatible lacks query-param, so measuring with the default scores lower). kgateway basic-auth works via TrafficPolicy basicAuth (native). Cilium rate-limiting/body-size were marked unsupported because there is no declarative standard or vendor path, but they are possible via raw CiliumEnvoyConfig (a low-level escape hatch on par with istio EnvoyFilter; unmeasured). Istio tls-passthrough stays unsupported even with the alpha flag (PILOT_ENABLE_ALPHA_GATEWAY_API) because it does not work in v1.4 (istio TLSRoute is officially conformant only for Terminate, passthrough unverified, issue #47366).

## 6. Non-functional / operational metrics (not features: performance, robustness, recovery)

| Implementation | health-check | load-test | failover-recovery | config-robustness |
|---|---|---|---|---|
| nginx | n/a | PASS | PASS | robust |
| envoy | PASS | PASS | PASS | robust |
| istio | n/a | PASS | PASS | robust |
| cilium | n/a | PASS | n/a | robust |
| kong | PASS | PASS | PASS | robust |
| kgateway | PASS | PASS | PASS | robust |
| traefik | n/a | PASS | PASS | robust |

> **failover-recovery detail** (recovery after a forced data-plane restart, separate rounds-ops campaign): nginx recovery ~13s, envoy recovery ~13s, istio no outage, cilium excluded (shared eBPF), kong recovery ~34s, kgateway no outage, traefik recovery ~13s. no outage=no traffic loss during pod replacement (outage 0), recovery ~Ns=normalized after about N seconds of gap. All confirmed disrupted by pod replacement (pod_changed).

> **health-check detail** (does active health checking eject an unhealthy backend from the pool. good 2 + bad 1 (/health 503) backends, supported when bad is fully removed, rounds-ops): nginx unsupported, envoy supported, istio unsupported, cilium unsupported, kong supported, kgateway supported, traefik unsupported. supported=active probe of envoy BackendTrafficPolicy / kong KongUpstreamPolicy / kgateway BackendConfigPolicy. unsupported=no active HC exposed (nginx Plus-only, istio is a mesh outlier, cilium/traefik not exposed).

> **config-robustness measurement condition**: 'does basic routing survive when all features are deployed at once'. The values above are based on the standard feature set (deterministic campaign). kong is sensitive to config-load, so under a heavier setup that also stacks the operational-test policies (rounds-ops campaign) the same item drops to fragile. This matches kong's all-or-nothing config model, and the robust label above is limited to the standard-setting scenario.

## 7. auth (theme: implementation/experimental mixed, migration-critical)

> Not a category but a **thematic cross-section**: auth is scattered across the taxonomy. **JWT=implementation (section-5 type, no standard)**, **ext-authz standard filter=experimental (GEP-1494)**, **ext-authz implementation=implementation**. It is the crux of ingress-nginx auth-url migration, so it is gathered in one place. Live verification values for 7 implementations (E8, E9), per-round automated measurement not integrated (unscored).

| Implementation | JWT | ext-authz (impl) | ext-authz (standard GEP-1494 filter) |
|---|---|---|---|
| nginx | Plus-only (OSS is Basic-only) | SnippetsFilter (low-level) | not implemented (404) |
| envoy | native JWKS | SecurityPolicy native | not implemented (UnsupportedValue) |
| istio | native JWKS | AuthzPolicy CUSTOM (mesh) | not implemented (InvalidFilter) |
| cilium | unsupported | unsupported | standard filter not implemented (passes)★ |
| kong | KGO secret issue (deny only) | OSS unsupported | not implemented (404) |
| kgateway | native JWKS | GatewayExtension native | standard filter not implemented (passes)★ |
| traefik | unsupported | forwardAuth native | accepts but 500 |

> ★ The GEP-1494 standard ExternalAuth filter is enforced by no implementation. envoy/nginx/istio/kong/traefik reject or error, while cilium/kgateway do not implement the standard filter, so unauthenticated traffic passes through as-is (silent no-op). GEP-1494 is at the experimental stage and does not specify a failure mode (fail-open/closed) (there is no 'MUST fail closed' wording in the spec; PR #4001 deferred failure semantics). cilium provides ext-authz only in 1.20, kgateway only via its vendor TrafficPolicy. Conclusion: the standard filter is not yet usable as production auth and a vendor CRD is required.

## 8. flake / data note (canary excluded, see section 3)

- (currently no non-canary flakes)

## 9. Data note: not-configured (not integrated into automated rounds)

> Items with no round data because they are not integrated into the automated round loop. They split into two kinds. (a) **auth-jwt/auth-extauth are measured**. They were live-verified (E8/E9) and the values are in the section-7 auth table. Only the automated-loop integration is deferred, so they merely show as `not-configured` in rounds, not as missing data. (b) **The rest are unmeasured** (no live logic, re-measurement targets). All are unscored, so grade is unaffected.

- nginx: measured (E8/E9, see section 7): auth-extauth, auth-jwt
- envoy: measured (E8/E9, see section 7): auth-extauth, auth-jwt
- istio: measured (E8/E9, see section 7): auth-extauth, auth-jwt
- cilium: measured (E8/E9, see section 7): auth-extauth, auth-jwt
- kong: measured (E8/E9, see section 7): auth-extauth, auth-jwt
- kgateway: measured (E8/E9, see section 7): auth-extauth, auth-jwt
- traefik: measured (E8/E9, see section 7): auth-extauth, auth-jwt
