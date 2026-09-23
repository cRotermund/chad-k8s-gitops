# Contributing

Changes to this repository can affect the Kubernetes cluster broadly. Keep them small, explicit, and easy to review.

## Before You Start

- Read the scope and delivery model in [README.md](README.md).
- Read [AGENTS.md](AGENTS.md) before editing manifests.
- Confirm that the proposed component is shared platform infrastructure, not application code.
- Confirm that required credentials and external dependencies can be supplied without committing secrets.

## Change Workflow

1. Branch from the default branch using `feat/<issue-number>/<short-description>` or `fix/<issue-number>/<short-description>` where an issue exists.
2. Make one logical infrastructure change.
3. Pin chart, image, or manifest versions; do not use floating versions or `latest`.
4. Validate YAML and Kubernetes resources using the checks documented by the component.
5. Review the rendered resources, RBAC, namespaces, sync policy, and Git diff.
6. Open a pull request describing the purpose, cluster impact, prerequisites, and rollback path.
7. Merge only after review and successful validation.

Do not bypass review by applying an unreviewed platform change directly to the cluster. If an emergency change is required, follow it with a repository change that records the intended state.

## Manifest Rules

- Keep one shared platform service per directory under `apps/`.
- Keep Argo CD `Application` definitions explicit about source, destination, project, and sync behavior.
- Preserve stable resource names and labels unless a migration is planned.
- Avoid broad cluster-scoped permissions; document every required `ClusterRole` and `ClusterRoleBinding`.
- Reference secrets by name or external-secret configuration; never include secret values.
- Keep generated files tied to their authoritative source and document the regeneration command.
- Do not add application-specific workloads merely because they use a shared platform service.

## Pull Request Checklist

- [ ] The change belongs in shared cluster infrastructure.
- [ ] Versions are pinned and the upgrade or installation impact is understood.
- [ ] YAML and Kubernetes validation passes.
- [ ] RBAC, namespaces, CRDs, storage, and resource settings were reviewed.
- [ ] No credentials, tokens, kubeconfigs, or rendered secrets are included.
- [ ] The PR describes cluster prerequisites, dependencies, and rollback considerations.
- [ ] Documentation reflects any new layout or operational procedure.

## Commit Messages

Use Conventional Commits where practical:

```text
feat(telemetry): add cluster metrics collector
feat(secrets): install external secret operator
fix(argocd): correct platform application destination
docs: clarify infrastructure scope
```
