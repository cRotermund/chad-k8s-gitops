# `paprika-mcp-go`

Argo CD `Application` for the `paprika-mcp-go` MCP server. The workload is
rendered from `infra/k8s/prod` in `github.com/cRotermund/paprika-mcp-go`
(branch `main`). This directory adds the cluster-side pieces the app repo
must not contain: its secret mapping and public routing.

## Managed Resources

- `ExternalSecret` `paprika-mcp-go` producing the Opaque Secret
  `paprika-mcp-go` in `chad-applications`.
- Traefik `Middleware` `paprika-mcp-go-strip-prefix` and `Ingress`
  `paprika-mcp-go` routing `apis.rotorlabs.io/paprika/mcp` to Service
  `paprika-mcp-go:8080` as `/mcp`.

The `chad-applications` namespace and `ghcr-pull-secret` come from the
`chad-applications-infra` application.

## AWS SSM Prerequisite

Create these `SecureString` parameters outside Git (the store role already
reads `/kubernetes/appsecrets/*`):

| Parameter | Secret key |
| --- | --- |
| `/kubernetes/appsecrets/chad-applications/paprika-mcp-go/mcp-token-sha256` | `MCP_TOKEN_SHA256` |
| `/kubernetes/appsecrets/chad-applications/paprika-mcp-go/paprika-email` | `PAPRIKA_EMAIL` |
| `/kubernetes/appsecrets/chad-applications/paprika-mcp-go/paprika-password` | `PAPRIKA_PASSWORD` |

## Routing

nginx terminates TLS for `apis.rotorlabs.io` and proxies `location /` to the
K3s server on port 80 with the original `Host`, where the bundled Traefik
matches this Ingress. No TLS is configured in-cluster.

## Verification

```bash
kubectl get externalsecret paprika-mcp-go -n chad-applications
kubectl get ingress paprika-mcp-go -n chad-applications
curl -s -o /dev/null -w '%{http_code}\n' https://apis.rotorlabs.io/paprika/mcp
```

An unauthenticated request should return `401`, not `404`.
