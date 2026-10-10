# External Secrets Operator

This component installs the pinned External Secrets Operator (ESO) chart and
the Kubernetes-side RBAC required for AWS web-identity authentication.

## Current Scope

The initial slice installs:

- ESO chart `0.20.1` from `https://charts.external-secrets.io`.
- ESO CRDs required for `ExternalSecret` and `ClusterSecretStore`.
- A dedicated `external-secrets/eso-aws-auth` service account.
- TokenRequest RBAC restricted to that service account by `resourceNames`.
- A `ClusterSecretStore` restricted to the `chad-applications` namespace.
- Explicit resource requests and limits.
- Disabled unused cluster and push-secret reconcilers.

The service account and `ClusterSecretStore` reference these IAM roles, which
are provisioned by the IaC repository:

- `k3s-external-secrets-auth`
- `k3s-ssm-parameter-read`

The SSM read role is limited to `/kubernetes/appsecrets/*`.

## Delivery

`application.yaml` uses Argo CD multi-source configuration:

- This repository supplies the values and Kubernetes RBAC resources.
- The pinned upstream chart supplies ESO and its CRDs.
- Argo CD creates the `external-secrets` namespace and self-heals the
  application.

The application assumes Argo CD already has access to this repository and that
the `default` Argo project permits the `external-secrets` namespace.

## Next Step

Validate a test `ExternalSecret` in `chad-applications` against a parameter
under `/kubernetes/appsecrets/`. Confirm that an unapproved namespace cannot
use the store. Do not commit AWS credentials, role secrets, or rendered
Kubernetes Secret objects.
