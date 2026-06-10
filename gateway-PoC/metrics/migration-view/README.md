# Starting-point view (migrating from ingress-nginx to the Gateway API)

[한국어](README_ko.md)

Question: **I run ingress-nginx. What carries over, and what breaks, if I move to each implementation?**

> The official Gateway API recommendation is to "pick a conformant-certified implementation." But even with conformant certification, the actual supported feature breadth ranges from 6 to 13. Comparing that gap is what this view does.

## Outputs
- [`README_tables.md`](README_tables.md): the migration checklist (4 difficulty grades, 26 items, per-implementation coverage), rendered directly on GitHub. This is the canonical output here.

> The pipeline also generates a styled single-page `report.html` (interactive) for the blog write-up. It is not committed here, since GitHub serves the data as Markdown and shows HTML only as source. Regenerate with `scripts/finalize.sh`.

## Why now (context)
- **ingress-nginx retirement confirmed** (announced 2025-11-11): maintenance ends March 2026, no security patches after that. The successor controller InGate was abandoned. The maintainers' recommendation is "migrate to the Gateway API".
- **Retirement drivers**: beyond the limits of being maintained by 1 to 2 volunteers, the design where the `configuration-snippet` and `server-snippet` annotations inject raw nginx directives became a security flaw. Its peak was IngressNightmare (CVE-2025-1974, CVSS 9.8), an unauthenticated RCE.
- **ingress2gateway 1.0** (2026-03-20): auto-converts more than 30 annotations and warns on items it cannot convert. This tool effectively draws the "migration-automation boundary".
- **"Before You Migrate"** (2026-02-27): the maintainers directly cataloged real traps such as regex semantic differences (prefix match, case handling), snippets, external auth, and mTLS.

## Four difficulty grades (the spine of the checklist)
- 🟢 **Standard migration**: Core/Extended-std, ingress2gateway auto-conversion, standard channel (in the maintainers' words, "as stable as Ingress"). Mostly carries over as-is.
- 🟡 **Caution migration**: experimental channel or different semantics, verification required. CORS, external auth, mTLS client, and TLSRoute are v1.4 experimental channel and slated for Standard promotion in v1.5.
- 🟠 **Vendor-locked**: no standard API, provided only via vendor CRDs, so lock-in recurs. rate-limit, body-size, and JWT are here.
- 🔴 **Migration-impossible**: the Gateway API has no equivalent at all (removed by design). snippets, basic auth.

## How this view differs from official material
- The official **conformance suite** is only "binary spec-compliance PASS/FAIL", **ingress2gateway** is only "whether mechanical conversion happens", and the **migration guide** is high-level.
- This view cross-compares, on one yardstick, live **measurement** (not declaration), the **vendor features** outside conformance scope (rate-limit, auth, body-size), and the **feature-breadth gap** within conformant implementations. For example, the CORS annotation converts, but on measurement only 3 of 7 pass.

## Sources (primary) and limits
- Sources: ingress-nginx retirement announcement (2025-11-11), "Before You Migrate" (2026-02-27), ingress2gateway 1.0 (2026-03-20), IngressNightmare CVE-2025-1974, Reddit "Gateway API for Ingress-NGINX, a Maintainer's Perspective" (robertjscott).
- Limits: **importance (high/medium/low) is directional.** With no public quantitative survey of ingress-nginx annotation usage frequency, it synthesizes the signal that maintainers singled out snippets as "the most depended on and most dangerous feature" and the emphasis in the migration guide. It uses verifiable signals (annotations, i2gw conversion coverage, measurement) as the primary basis.

For the rigor (spec) lens, see [`../conformance-view/`](../conformance-view/).
