# Kubernetes Infrastructure GitOps

This repository is the GitOps source of truth for platform infrastructure deployed to the Kubernetes cluster by Argo CD.

It is intentionally separate from repositories containing application source code or application-specific deployment configuration. The components managed here should support the cluster ecosystem broadly rather than serve one individual use case.

## Scope

Components that belong in this repository include:

- Secret-management operators and their cluster-level configuration.
- Telemetry tooling for metrics, logs, and traces.
- Ingress, certificate, policy, storage, and other shared platform services.
- Argo CD `Application` definitions and the bootstrap resources needed to reconcile them.
- Cluster-wide configuration that is safe to review and store in Git.

The following do not belong here:

- Application source code, container build definitions, or application tests.
- Deployments that are specific to one application or product use case.
- Secret values, kubeconfigs, private keys, or repository credentials.
- Generated output that has a more authoritative source in another repository.
- Manual changes made directly to the cluster instead of through Git.

## Repository Layout

The repository starts with documentation only. As platform components are added, use this layout:

```text
bootstrap/
  Argo CD root or prerequisite Application definitions
apps/
  One directory per shared platform service and its Argo CD Application
components/
  Reusable Kubernetes configuration that is consumed by platform services
```

Keep each platform service independently reviewable and independently removable. Prefer an Argo CD `Application` per service instead of combining unrelated components into one large manifest.

## Delivery Model

1. A reviewed change is merged into the default branch.
2. Argo CD reads the configured path in this repository.
3. Argo CD reconciles the declared platform applications into the cluster.
4. Drift and sync failures are investigated in Argo CD and corrected through Git.

The exact Argo CD project, repository URL, destination cluster, and sync policy must be explicit in the bootstrap/application manifests. Do not assume that a local `kubectl apply` is the normal delivery mechanism.

## Getting Started

Before adding a platform service, confirm:

- Argo CD is installed and has access to this repository.
- The target cluster and Argo CD project are known.
- The service has a cluster-wide or shared-platform purpose.
- Any required credentials can be provisioned outside Git or through a supported secret operator.
- The chart or manifests have a pinned, reviewable version.

Review the relevant Argo CD `Application` before applying or enabling it. Platform services can affect every workload in the cluster, so namespace, permissions, CRDs, resource limits, storage, and upgrade behavior require explicit review.

## Validation

Validate YAML syntax and Kubernetes resources locally before opening a pull request. The repository will add component-specific validation as the first deployable services are introduced. At minimum, inspect the rendered resources for:

- Namespaces, cluster-scoped resources, and ownership boundaries.
- RBAC permissions and service-account usage.
- Resource requests, limits, persistence, and upgrade strategy.
- Secret references without embedded secret values.
- Argo CD sync, prune, self-heal, and dependency behavior.

## Security

- Never commit credentials, tokens, certificates, private keys, kubeconfigs, or `.env` files.
- Store secret values in the cluster or an approved external secret manager.
- Use secret-operator definitions to reference external secret stores, not to embed their values.
- Minimize cluster-scoped RBAC and document why it is required.
- Treat changes to shared infrastructure as production changes.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the change workflow and pull request checklist. Repository-specific agent guidance is in [AGENTS.md](AGENTS.md).
