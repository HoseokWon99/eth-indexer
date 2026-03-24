# Grafana Unreachable via Gateway API

## Root Cause

The `URLRewrite` filter in the HTTPRoute stripped the `/grafana` prefix before forwarding
requests to Grafana. Grafana received requests at `/` and had no awareness of the subpath,
so its login redirect pointed to `/login` (no prefix). The browser followed the redirect to
`http://host.minikube.internal/login`, which matched no HTTPRoute rule — connection failed.

Two misconfigurations combined to cause this:

1. **HTTPRoute** stripped `/grafana` via `URLRewrite ReplacePrefixMatch: /`
2. **Grafana** had `GF_SERVER_SERVE_FROM_SUB_PATH=false` and `GF_SERVER_ROOT_URL` with no
   subpath, so it generated bare `/login` redirects with no prefix

## Fix Points

### 1. `k8s/monitoring/grafana/deployment.yaml`

Tell Grafana it lives under `/grafana` so it prefixes its own redirects correctly:

```yaml
- name: GF_SERVER_ROOT_URL
  value: "%(protocol)s://%(domain)s/grafana"
- name: GF_SERVER_SERVE_FROM_SUB_PATH
  value: "true"
```

### 2. `k8s/ingress.yaml` — remove URLRewrite from `/grafana` rule

With `SERVE_FROM_SUB_PATH=true`, Grafana expects the full `/grafana/...` path from the
gateway. Do not strip the prefix:

```yaml
# Before (broken)
- matches:
    - path:
        type: PathPrefix
        value: /grafana
  filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /   # ← strips /grafana before forwarding
  backendRefs:
    - name: grafana
      port: 3000

# After (fixed)
- matches:
    - path:
        type: PathPrefix
        value: /grafana
  backendRefs:                    # ← no filter; /grafana/... forwarded as-is
    - name: grafana
      port: 3000
```

### 3. `k8s/ingress.yaml` — fix `api-server` backend port

The `api-server` Service exposes port `80` (targetPort `8080`). The HTTPRoute backend port
must reference the Service port, not the container port:

```yaml
backendRefs:
  - name: api-server
    port: 80   # was 8080
```

### 4. `k8s/ingress.yaml` — remove non-existent `indexer-server` backend

No Service named `indexer-server` exists. The stale rule caused `ResolvedRefs: False` on
the HTTPRoute. Removed the `/indexer` rule entirely.
