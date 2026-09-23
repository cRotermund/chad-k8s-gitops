# AGENTS.md

## Repository Purpose

This is the GitOps repository for shared Kubernetes platform infrastructure. Argo CD consumes the manifests here and reconciles services that support the cluster as a whole, such as secret management, telemetry, ingress, policy, storage, and other foundational tooling.

Application source code and application-specific deployment state belong in their own repositories.

## Scope

- Keep Argo CD bootstrap resources under `bootstrap/`.
- Keep one shared platform service per directory under `apps/`.
- Keep reusable platform configuration under `components/` when it is genuinely shared.
- Keep documentation aligned with the actual deployment and recovery workflow.

## Safety Rules

- Never commit secrets, `.env` files, kubeconfigs, credentials, private keys, or certificates containing private material.
- Reference secret values through cluster-managed secrets or an approved external secret manager.
- Do not add application code or application-specific workloads to this repository.
- Pin Helm charts, container images, and manifest versions. Do not use `latest` or floating versions.
- Treat cluster-scoped RBAC, CRDs, admission policies, and changes to Argo CD sync behavior as high-impact changes.
- Do not change Argo CD destination, project, pruning, or self-healing behavior without calling it out in the pull request.
- Do not apply unreviewed changes directly to the cluster as a substitute for Git history.

## Validation

For every manifest change:

- Parse and validate the YAML and Kubernetes resources with the repository's configured tooling.
- Review namespaces, cluster-scoped resources, RBAC, resource limits, storage, and secret references.
- Check Argo CD dependencies, sync options, prune behavior, and rollback implications.
- Review the complete Git diff before proposing the change.

Do not assume that a successful YAML parse means a safe deployment.

## Editing Guidance

- Keep YAML two-space indented, LF-terminated, and free of trailing whitespace.
- Prefer the smallest change that establishes the intended platform behavior.
- Preserve stable resource names and labels unless a migration is explicitly planned.
- Keep related configuration together, but do not combine unrelated platform services into one manifest.
- Add concise documentation when a component introduces a prerequisite, operational procedure, or recovery step.
