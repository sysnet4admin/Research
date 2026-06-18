# Gateway API PoC, starting-point view (ingress-nginx → Gateway API v1.4 migration)

> **The official Gateway API recommendation is to 'pick a conformant implementation.' But even when conformant, the actual supported feature breadth ranges from 6 to 13. Comparing that gap is what this view does.**

> **What sets this view apart**: unlike official conformance (declared PASS/FAIL) and ingress2gateway (whether mechanical conversion happens), it cross-compares, on one yardstick, live cluster **measurement** + **implementation features** outside conformance scope (rate-limit, auth, body-size) + the **feature-breadth gap** within conformant implementations. For the rigor (spec) view see `../conformance-view/`.

> **Measurement basis: Gateway API v1.4** (2026-06 measurement time, ingress2gateway 1.1.0). Difficulty grades are based on this version. **v1.5 (released 2026-04-21) new features** (mTLS client etc.) are outside the v1.4 measurement scope, so they are marked `TBD(v1.5)` and are targets for the next re-baseline (re-baseline is after Cilium 1.20 stable, expected late July). By contrast **CORS, external auth, and TLSRoute were already measured on all 7 in the v1.4 experimental channel**, and if promoted to the standard channel in v1.5 they can move from 🟡 to 🟢. Cell-value sources are the same as the rigor view's measurement (same measurement data).

## 1. Four migration-difficulty grades

| Grade | Meaning |
|---|---|
| **🟢 Standard migration** | Core/Extended-std, i2gw auto-conversion, standard channel is stable. Mostly carries over as-is |
| **🟡 Caution migration** | Experimental channel or different semantics, verification required. Many to be promoted in v1.5 |
| **🟠 Vendor-locked** | No standard API, only implementable via each implementation's CRD, so vendor lock-in recurs |
| **🔴 Migration-impossible** | No equivalent at all (redesign required) |

## 2. Per-implementation coverage (by measurable items)

> *"If I move my ingress-nginx to this implementation, how many per grade actually work."* It counts only the items actually measured per implementation. Excluded are the 🔴 migration-impossible grade, items judged only at the Gateway API spec level regardless of implementation (`(not measured)` in the table), and structural rows with no measurement mapping (e.g. mTLS client=`TBD(v1.5)`). So the per-grade denominator can be smaller than the row count in the section-3 checklist (e.g. 🟡 is based on 7 of the 8 checklist rows, excluding mTLS).

| Implementation | 🟢 Standard(11) | 🟡 Caution(7) | 🟠 Implementation(6) | Total |
|---|---|---|---|---|
| nginx | 11/11 | 5/7 | 3/6 | **19/24** |
| envoy | 11/11 | 7/7 | 5/6 | **23/24** |
| istio | 11/11 | 6/7 | 4/6 | **21/24** |
| cilium | 11/11 | 4/7 | 0/6 | **15/24** |
| kong | 8/11 | 1/7 | 3/6 | **12/24** |
| kgateway | 11/11 | 6/7 | 4/6 | **21/24** |
| traefik | 10/11 | 5/7 | 4/6 | **19/24** |

> Supported = **works** (includes low-level-config/snippet). It counts only whether it works; the quality gap (native vs low-level) is shown by the section-3 detail table. External auth is based on implementation native (the GEP-1494 standard filter is enforced by no one, rigor view section 7).

## 3. Migration checklist (26 items, by difficulty group)

> **Legend: i2gw conversion** (ingress2gateway 1.1.0 **run directly per annotation**, before/after manifests under `migration/i2gw/`): `✓` auto-converted / `~` partial/best-effort (or some annotations rejected) / `✗` not converted (manual redesign) / `native` a base Ingress feature so not a conversion target (easiest). **Converted ≠ works**. The implementation cell (PASS/native etc.) shows actual support.

### 🟢 Standard migration (11)

| Feature | ingress-nginx annotation | Importance | GW API v1.4 | i2gw | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|---|---|---|
| host routing | `(native Ingress rules)` | High | Core | native | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| path routing | `(native rules, pathType)` | High | Core | native | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| header routing | `canary-by-header` | Medium | Core | ✓ | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| TLS termination | `(native tls.secretName)` | High | Core | native | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| HTTPS redirect | `ssl-redirect, force-ssl-redirect` | High | Core(RequestRedirect) | ~ | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| path redirect | `permanent-redirect, temporal-redirect, app-root` | Medium | Core/Ext(RequestRedirect) | ✓ | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| URL rewrite | `rewrite-target` | High | Extended-std(URLRewrite) | ~ | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| canary (weighted) | `canary, canary-weight, canary-weight-total` | High | Core(weighted backendRefs) | ✓ | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| request mirroring | `mirror-target, mirror-host` | Low | Extended-std(RequestMirror) | ✗ | PASS | PASS | PASS | PASS | n/a | PASS | FAIL |
| header modification (request/response) ※ | `proxy-set-headers, custom-headers, x-forwarded-prefix` | High | Core(request)/Ext(response) | ✗ | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| websocket | `(native, proxy upgrade)` | Medium | Extended-std(WebSocket) | native | PASS | PASS | PASS | PASS | PASS | PASS | PASS |

> ※ traps/notes:
  - **header modification (request/response)**: x-forwarded-prefix is silently dropped from the output with no filter (no rejection notice either), and proxy-set-headers/custom-headers are also not converted. i2gw measurement emitted 0 equivalents

### 🟡 Caution migration (8)

| Feature | ingress-nginx annotation | Importance | GW API v1.4 | i2gw | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|---|---|---|
| regex path ※ | `use-regex + capture group` | High | impl-specific(RegularExpression) | ~ | supported | supported | supported | supported | supported | supported | supported |
| timeout ※ | `proxy-connect/read/send-timeout` | High | Standard(v1.2) | ~ | FAIL | PASS | PASS | PASS | FAIL | PASS | FAIL |
| CORS ※ | `enable-cors, cors-allow-*, cors-expose-headers, cors-max-age` | High | Extended-exp(v1.4) | ✓ | n/a | PASS | PASS | FAIL | n/a | PASS | FAIL |
| external auth (incl. OIDC) ※ | `auth-url, auth-signin, auth-snippet` | High | Extended-exp(GEP-1494, v1.4) | ✗ | SnippetsFilter (low-level) | SecurityPolicy native | AuthzPolicy CUSTOM (mesh) | unsupported | OSS unsupported | GatewayExtension native | forwardAuth native |
| backend re-encryption | `backend-protocol: HTTPS, proxy-ssl-*` | Medium | Core(BackendTLSPolicy GA v1.4) | ~ | PASS | PASS | PASS | FAIL | FAIL | FAIL | PASS |
| gRPC routing | `backend-protocol: GRPC` | Medium | Core(separate GRPCRoute) | ✓ | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| mTLS client auth ※ | `auth-tls-secret, auth-tls-verify-client, auth-tls-verify-depth` | Medium | not in v1.4, added in v1.5(2026-04) | ✗ | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) |
| TLS passthrough ※ | `ssl-passthrough` | Medium | Extended-exp(TLSRoute) | ✓ | supported | supported | unsupported | supported | unsupported | supported | supported |

> ※ traps/notes:
  - **regex path**: nginx ignores case on prefix matches while GW is case-sensitive on full matches, so moving as-is risks a silent 404 (Before You Migrate). capture-group rewrite is mostly unsupported
  - **timeout**: nginx's 3 timeouts must be merged into GW's 2 (request/backendRequest), i2gw does a best-effort conversion
  - **CORS**: experimental channel, slated for Standard promotion in v1.5
  - **external auth (incl. OIDC)**: OIDC is usually implemented via oauth2-proxy at auth-url, so it is included in this row. Targets v1.5 GA together with mTLS client auth
  - **mTLS client auth**: The standard frontendValidation field is entirely absent from the v1.4 Gateway CRD (confirmed directly on the experimental v1.4.1 CRD: tls has only certificateRefs/mode/options). v1.5 (released 2026-04-21, GEP-91) added it as frontendValidation.caCertificateRefs (AllowValidOnly/AllowInsecureFallback). Our benchmark is pinned to v1.4, so it is unmeasured, hence TBD(v1.5). Measurable when the v1.5 re-baseline runs after Cilium 1.20 stable (expected late July)
  - **TLS passthrough**: Measured on all 7 via TLSRoute (passthrough). TLSRoute targets v1.5 GA (PR #4064)

### 🟠 Vendor-locked (6)

| Feature | ingress-nginx annotation | Importance | GW API v1.4 | i2gw | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|---|---|---|
| rate limiting | `limit-rps, limit-rpm, limit-connections, limit-rate, limit-whitelist` | High | no standard, implementation policy CRD | ✗ | native | native | low-level-config | unsupported | native | native | native |
| request body size limit | `proxy-body-size` | High | no standard (i2gw warns too) | ✗ | native | unsupported | low-level-config | unsupported | native | unsupported | native |
| session affinity ※ | `affinity: cookie, session-cookie-name/expires` | Medium | spec exists but cookie config is impl-dependent | ✗ | n/a | PASS | n/a | n/a | n/a | PASS | n/a |
| JWT validation | `(auth-snippet / plugin)` | High | no standard, implementation | ✗ | Plus-only (OSS is Basic-only) | native JWKS | native JWKS | unsupported | KGO secret issue (deny only) | native JWKS | unsupported |
| IP allow/deny ※ | `whitelist-source-range, denylist-source-range` | Medium | no standard filter, implementation policy | ✗ | unsupported | native | native | unsupported | native | unsupported | native |
| basic auth ※ | `auth-type: basic, auth-secret, auth-realm` | Medium | no standard, implementation policy | ✗ | native | native | unsupported | unsupported | unsupported | native | native |

> ※ traps/notes:
  - **session affinity**: i2gw measurement rejected all 3 (affinity/session-cookie-*) with 'Session affinity is not supported', emitting 0 affinity config in the output
  - **IP allow/deny**: Measured on all 7 via implementation CIDR policy. i2gw only emits impl-specific config
  - **basic auth**: Not in the standard Gateway API but implemented by implementations (envoy SecurityPolicy, traefik/kong, NGF AuthenticationFilter), so classified 🟠. Measured on all 7

### 🔴 Migration-impossible (1)

| Feature | ingress-nginx annotation | Importance | GW API v1.4 | i2gw | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|---|---|---|
| config snippet ※ | `configuration-snippet, server-snippet, stream-snippet` | High | no equivalent by design (cause of IngressNightmare) | ✗ | (not measured) | (not measured) | (not measured) | (not measured) | (not measured) | (not measured) | (not measured) |

> ※ traps/notes:
  - **config snippet**: Used in practice (custom headers, timeouts, buffer sizes, path blocking, etc.). But most of those use cases are already absorbed into typed features (measured in other rows like header modification/timeout). The remaining essence, injecting arbitrary nginx directives, has no standard and no safe implementation substitute, so measuring it is meaningless (not a measurement target). Disabled by default for security since v1.9.0 (CVE-2021-25742). Only NGF retains a snippet option (the feature behind that CVE)

## 4. How to read / sources / limits

- **Reading cells**: 🟢🟡 grades are live `PASS/FAIL/n/a`. 🟠 implementation is the `native/low-level-config/unsupported` matrix. auth uses live-verified values (rigor section 7). `(not measured)` is an item not measured per implementation but judged only at the Gateway API spec level (e.g. snippet has no equivalent in any implementation).
- **i2gw conversion**: a **measured value** that **ran ingress2gateway 1.1.0 directly** on a sample Ingress per annotation and recorded conversion results/warnings (not a research estimate). before/after manifests + logs + classification basis are under `migration/i2gw/` (ingress/, gateway/, logs/, results.json). `✓`=auto-converted, `~`=partial/some rejected, `✗`=not converted (manual redesign), `native`=a base Ingress feature so not a conversion target.
- **Excluded from the checklist**: Gateway API new standard features not in ingress-nginx, such as method matching and query-param matching, are not in this checklist. They are not things to "carry over" in migration but features gained additionally after moving (measured in the rigor view).
- **Importance (high/medium/low)**: real-world ingress-nginx usage importance. It is directional. With no public quantitative survey, it synthesizes the signal that maintainers singled out snippet as "most depended on + most dangerous" and the emphasis in the migration guide.
- **Sources (primary)**: ingress-nginx retirement announcement (2025-11-11), "Before You Migrate" (2026-02-27), ingress2gateway 1.0 (2026-03-20), IngressNightmare CVE-2025-1974, Reddit "Gateway API for Ingress-NGINX, a Maintainer's Perspective".
- **Limits**: many 🟡 (CORS, external auth, mTLS client, TLSRoute) are v1.4 experimental channel and slated for Standard promotion in v1.5, so the grade may rise depending on timing. 🔴 snippet is permanently unsupported by design (redesign required).
