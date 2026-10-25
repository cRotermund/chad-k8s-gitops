# External Secrets with AWS Parameter Store

## Status

Authoritative design and implementation plan. This document is the contract between the two repositories involved in this integration. It is not itself a deployable manifest set.

The two repositories are:

1. The **IaC repository**, which provisions the k3s cluster and owns the AWS and edge infrastructure supporting the home lab.
2. This **GitOps repository**, which assumes Argo CD is already installed and working and owns Argo-managed shared Kubernetes platform resources.

## Goal

Allow approved application namespaces to consume selected values from AWS Systems Manager Parameter Store as ordinary Kubernetes `Secret` objects, without storing AWS access keys or secret values in Git.

The first implementation will use:

- External Secrets Operator (ESO).
- AWS Systems Manager Parameter Store.
- Kubernetes service-account tokens exchanged with AWS STS using OIDC federation.
- A path-based OIDC issuer at `https://apis.rotorlabs.io/aws-oidc`.
- A restricted ESO `ClusterSecretStore`.
- Argo CD for delivery of the Kubernetes resources.
- Terraform or another AWS IaC repository for IAM resources.

## Non-goals

This design does not:

- Store secret values, AWS credentials, or signing keys in this repository.
- Make application deployments part of this platform repository.
- Use EKS Pod Identity or IRSA. The cluster is k3s on EC2, not EKS.
- Give applications direct AWS credentials.
- Grant every namespace access to every SSM parameter.
- Bootstrap or install Argo CD. Argo CD is a prerequisite for this implementation.

## End-to-end flow

The complete request path is:

```text
Application ExternalSecret
        |
        v
Restricted ClusterSecretStore
        |
        v
ESO requests a short-lived token for eso-aws-auth
        |
        v
Kubernetes signs the token with its service-account signing key
        |
        v
ESO sends the token to AWS STS
        |
        v
AWS validates the token through the IAM OIDC provider
        |
        v
ESO authentication role
        |
        v
STS AssumeRole into the SSM read role
        |
        v
AWS Systems Manager Parameter Store
        |
        v
Kubernetes Secret in the application namespace
```

There are two separate AWS roles on purpose:

1. `k3s-external-secrets-auth` is trusted by the Kubernetes OIDC identity and may assume the SSM role.
2. `k3s-ssm-parameter-read` is trusted only by the ESO authentication role and has the SSM permissions.

This separation lets the Kubernetes identity trust and the data-access policy evolve independently.

## Why the issuer is path-based

The available SAN certificate covers `apis.rotorlabs.io`, but not a new hostname such as `oidc.rotorlabs.io`. The issuer can include a path, so the stable issuer will be:

```text
https://apis.rotorlabs.io/aws-oidc
```

The path is part of the issuer identity. It must remain identical in all of these places:

- k3s service-account issuer configuration.
- The AWS IAM OIDC provider.
- The `iss` claim in Kubernetes-issued tokens.
- The OIDC discovery document.
- AWS IAM trust-policy condition keys.

Do not add a trailing slash. These are different issuer values:

```text
https://apis.rotorlabs.io/aws-oidc
https://apis.rotorlabs.io/aws-oidc/
```

Changing the path later is an identity migration and should not be treated as a normal Nginx routing change.

## Public OIDC endpoints

AWS needs two unauthenticated HTTPS endpoints:

```text
https://apis.rotorlabs.io/aws-oidc/.well-known/openid-configuration
https://apis.rotorlabs.io/aws-oidc/openid/v1/jwks
```

The discovery response must identify the same issuer and advertise the JWKS URL, conceptually:

```json
{
  "issuer": "https://apis.rotorlabs.io/aws-oidc",
  "jwks_uri": "https://apis.rotorlabs.io/aws-oidc/openid/v1/jwks"
}
```

The JWKS response contains public signing keys. It does not contain the private service-account signing key or any application secret.

Nginx should expose only these exact GET endpoints under `/aws-oidc`. Other paths under that prefix should return `404` or `403`. Do not put login, OAuth, basic authentication, or an authentication redirect in front of these endpoints; AWS must retrieve them anonymously.

The existing Nginx is a good place for this routing if it runs independently of the cluster. If it is an in-cluster ingress, the design has a recovery dependency: AWS needs the ingress in order to validate tokens, while the ingress needs the cluster to be healthy. External Nginx is preferred.

## Phase 0: Confirm the infrastructure boundary

Before making Kubernetes or IAM changes, document these values:

| Value | Required meaning |
| --- | --- |
| OIDC issuer | Exactly `https://apis.rotorlabs.io/aws-oidc` |
| AWS account | Account containing the IAM roles and parameters |
| AWS region | Region containing the parameters |
| SSM path | For example `/platform/production/` |
| Nginx location | The server or edge system that owns `apis.rotorlabs.io` |
| Argo destination | Cluster server URL or registered cluster name |
| Argo project | Project permitted to deploy shared platform services |
| Repository URL | URL Argo CD uses to read this repository |
| Initial namespace | `chad-applications` |

The AWS account, region, role ARNs, and SSM path are configuration inputs. They must not be guessed in manifests.

## Ownership and automation model

The OIDC integration crosses cluster, edge, AWS, and Kubernetes delivery boundaries. There are only two repositories, so the IaC repository owns all infrastructure outside Argo-managed Kubernetes application resources:

| Concern | Recommended home | Why |
| --- | --- | --- |
| k3s service-account issuer and signing-key configuration | IaC repository | These settings belong to cluster control-plane provisioning and affect every service-account token. |
| Public DNS, TLS, and Nginx OIDC routes | IaC repository | The IaC repository is authoritative for the edge infrastructure supporting this cluster. |
| AWS IAM OIDC provider, roles, and policies | AWS Terraform/IaC repository | IAM trust and SSM permissions are AWS resources and should have one authoritative state. |
| ESO Helm release, Kubernetes service account, RBAC, and `ClusterSecretStore` | This GitOps repository | Argo CD should reconcile shared Kubernetes platform resources. |
| Human-readable contract, verification steps, and recovery procedure | This GitOps repository, with references to the IaC repository | Operators looking at the platform deployment need to understand the complete dependency chain. |

The endpoint itself should not be manually maintained as a static document. Kubernetes produces the discovery and JWKS responses from its service-account issuer configuration and signing keys. Nginx should only provide stable HTTPS routing to those responses.

### What should remain manual

Manual work is appropriate for the initial bootstrap when the automation needed to manage itself does not yet exist. For example:

1. Provision the first public DNS and TLS path.
2. Apply the initial k3s issuer configuration during a controlled control-plane rollout.
3. Apply the first Terraform state or import pre-existing IAM resources.

Each manual bootstrap action should be immediately followed by codification in its authoritative repository. The manual procedure should be retained as a recovery SOP, not treated as the desired day-to-day workflow.

### What should be automated

The steady-state workflow should be:

1. The IaC repository provisions or updates the issuer prerequisites, edge route, IAM OIDC provider, and IAM roles.
2. This GitOps repository deploys ESO and the Kubernetes-side references to the already-provisioned role ARNs.
3. Argo CD reports drift or health failures.
4. Changes are reviewed and applied through the owning repository rather than edited directly on the cluster, AWS console, or Nginx host.

Avoid having both repositories create or manage the same IAM role, DNS record, Nginx route, or Kubernetes resource. Cross-repository dependencies should be represented as documented outputs, such as:

- OIDC issuer URL.
- IAM OIDC provider ARN.
- ESO authentication role ARN.
- SSM read role ARN.
- Approved SSM path.
- Approved namespace list.

## Standard operating procedure location

This document is the end-to-end SOP for the integration. The IaC repository should contain the executable infrastructure definitions and the detailed procedures for applying them. This repository should contain the Kubernetes delivery procedures and the cross-repository acceptance checks.

The documentation split is:

- **This document:** architecture, trust flow, repository contract, dependency order, GitOps implementation, acceptance checks, rollback, and owner handoffs.
- **IaC repository:** k3s issuer flags, signing-key storage and rotation, DNS, TLS, Nginx routes, upstream TLS, firewall rules, IAM OIDC provider, IAM roles, Terraform variables, plan/apply procedure, imports, and infrastructure recovery.

The two repositories must not duplicate live resource definitions. This document may show examples and expected outputs, but the IaC repository is authoritative for all cluster provisioning, edge, AWS, and IAM resources. This repository is authoritative for ESO and its Kubernetes resources.

Both repositories should document normal changes and recovery. Recovery must explain how to restore public discovery and JWKS endpoints, re-establish the IAM trust chain, and confirm that existing Kubernetes Secrets remain available while ESO is recovering.

## Repository contract

The IaC repository must publish or make discoverable these values before the GitOps implementation is merged:

| Output | Consumer | Purpose |
| --- | --- | --- |
| OIDC issuer URL | Both repositories | Must be exactly `https://apis.rotorlabs.io/aws-oidc`. |
| IAM OIDC provider ARN | IaC operators and audit records | Identifies the AWS trust anchor. |
| ESO authentication role ARN | GitOps repository | Annotated on `eso-aws-auth` and trusted by the Kubernetes OIDC subject. |
| SSM read role ARN | GitOps repository | Referenced by the `ClusterSecretStore`. |
| AWS region | GitOps repository | Configures the ESO AWS provider. |
| Approved SSM path | Both repositories | Limits IAM resources and external-secret references. |
| Approved namespace list | GitOps repository | Limits `ClusterSecretStore` usage. |

The GitOps repository must not silently invent any of these values. Changes to the issuer URL, role ARNs, SSM path, or namespace boundary require coordinated review in both repositories.

## Phase 1: Configure the OIDC issuer in k3s

### What changes

Configure every k3s server with a consistent service-account issuer:

```text
service-account-issuer=https://apis.rotorlabs.io/aws-oidc
```

Use k3s-managed signing-key settings unless the current installation requires explicit paths. If explicit settings are needed, all servers must use the same signing key material.

### Why it matters

Kubernetes service-account tokens contain an `iss` claim. AWS will only trust tokens whose issuer matches the IAM OIDC provider exactly. Without a stable issuer, AWS cannot distinguish a token from this cluster from a token issued by another system.

### Key handling

The service-account signing key is a cluster control-plane credential. It must:

- Remain on the k3s control-plane nodes or an approved secure backup.
- Never be committed to Git.
- Be consistent across k3s server nodes.
- Be rotated only with an explicit token and IAM compatibility plan.

Roll out this change one control-plane node at a time according to the k3s high-availability procedure. Inspect the current k3s configuration before adding flags; do not overwrite existing service-account settings blindly.

## Phase 2: Add the Nginx routes

### What changes

Add exact routes for:

```text
/aws-oidc/.well-known/openid-configuration
/aws-oidc/openid/v1/jwks
```

The public path may need to be stripped before forwarding to the Kubernetes API server:

```text
Public:   /aws-oidc/.well-known/openid-configuration
Upstream: /.well-known/openid-configuration

Public:   /aws-oidc/openid/v1/jwks
Upstream: /openid/v1/jwks
```

The exact rewrite depends on the existing Nginx configuration. The upstream connection should validate the Kubernetes API server certificate and use a tightly restricted firewall path.

### Why it matters

AWS STS validates the Kubernetes token by downloading the discovery document and signing keys. If either endpoint is unavailable, incorrectly rewritten, authenticated, or served with an invalid certificate, role assumption fails.

### Required Nginx behavior

- Serve the existing valid public TLS certificate for `apis.rotorlabs.io`.
- Allow anonymous GET requests to the two OIDC endpoints.
- Do not redirect those requests to a login page.
- Do not expose the entire Kubernetes API through the OIDC prefix.
- Return `404` for unrecognized paths under `/aws-oidc`.
- Preserve the exact issuer and JWKS URLs in the discovery response.

## Phase 3: Validate OIDC before AWS changes

Run these checks from the control plane:

```bash
kubectl get --raw /.well-known/openid-configuration
kubectl get --raw /openid/v1/jwks
```

Run the public checks from a machine outside the cluster:

```bash
curl https://apis.rotorlabs.io/aws-oidc/.well-known/openid-configuration
curl https://apis.rotorlabs.io/aws-oidc/openid/v1/jwks
```

Confirm that:

- Both responses are successful HTTPS responses.
- The discovery document has `issuer` equal to `https://apis.rotorlabs.io/aws-oidc`.
- The discovery document's `jwks_uri` is `https://apis.rotorlabs.io/aws-oidc/openid/v1/jwks`.
- The JWKS response contains public keys.
- No authentication middleware is involved.

Create a short-lived test token:

```bash
kubectl create token default --namespace default --audience sts.amazonaws.com
```

Inspect only its decoded claims. Do not publish the complete token. The claims must include:

```text
iss = https://apis.rotorlabs.io/aws-oidc
aud includes sts.amazonaws.com
sub identifies the expected service account
```

Do not create the AWS IAM OIDC provider until these checks pass.

## Phase 4: Create AWS IAM resources in Terraform

These resources belong in the AWS IaC repository, not this repository.

### 4.1 IAM OIDC provider

Create an IAM OIDC provider for:

```text
https://apis.rotorlabs.io/aws-oidc
```

Trust the audience:

```text
sts.amazonaws.com
```

AWS will use the issuer's discovery and JWKS endpoints to validate tokens.

### 4.2 ESO authentication role

Create `k3s-external-secrets-auth`.

Its trust policy must restrict both the audience and subject:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/apis.rotorlabs.io/aws-oidc"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "apis.rotorlabs.io/aws-oidc:aud": "sts.amazonaws.com",
          "apis.rotorlabs.io/aws-oidc:sub": "system:serviceaccount:external-secrets:eso-aws-auth"
        }
      }
    }
  ]
}
```

Its permissions should only allow assumption of the target SSM role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::<account-id>:role/k3s-ssm-parameter-read"
    }
  ]
}
```

Do not give this role broad SSM permissions.

### 4.3 SSM parameter-read role

Create `k3s-ssm-parameter-read`.

Its trust policy should name only the authentication role as principal:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<account-id>:role/k3s-external-secrets-auth"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Its permissions should be limited to the approved parameter path:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:<region>:<account-id>:parameter/platform/production/*"
    }
  ]
}
```

Add `kms:Decrypt` only if the parameters use a customer-managed KMS key, and scope it to that key ARN. Do not grant write, delete, tagging, path-discovery, or wildcard permissions unless a later use case proves they are necessary.

## Phase 5: Add the GitOps repository structure

Argo CD is assumed to be installed, configured with repository access, and already able to reconcile this repository. No Argo bootstrap resource is required for this integration.

The intended structure is:

```text
apps/
  external-secrets/
    application.yaml
    values.yaml
    cluster-secret-store.yaml
    rbac.yaml
    README.md
```

The `Application` may be added to an existing Argo application hierarchy if one already exists. If this repository is currently reconciled from a known root application, the ESO application should follow that repository's established pattern rather than introducing a second bootstrap mechanism.

### `apps/external-secrets/application.yaml`

This Argo `Application` installs the pinned ESO Helm chart into the `external-secrets` namespace.

It should:

- Pin the chart version.
- Install CRDs.
- Use a stable service account name.
- Set resource requests and limits.
- Preserve restricted pod security defaults.
- Disable unused ESO reconcilers where practical.
- Disable broad service-account token creation if the chart version supports it.

### `apps/external-secrets/rbac.yaml`

This grants ESO permission to create a short-lived token only for:

```text
external-secrets/eso-aws-auth
```

The `resourceNames` restriction is important. A compromised ESO controller should not be able to request tokens for arbitrary service accounts.

### `eso-aws-auth` service account

The configuration must also create the dedicated service account with the authentication role ARN in its metadata:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eso-aws-auth
  namespace: external-secrets
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/k3s-external-secrets-auth
```

The `eks.amazonaws.com/role-arn` annotation name is used by ESO's AWS provider even though this is not an EKS cluster. No EKS mutating webhook is expected or required here. ESO reads the annotation, requests a token for this service account, and uses the token with AWS STS. The service account does not contain an AWS credential Secret.

The annotation is metadata only; the actual authorization comes from the IAM OIDC provider and the role trust policy. The namespace, service-account name, annotation, and IAM trust-policy `sub` condition must all agree.

### `apps/external-secrets/cluster-secret-store.yaml`

This defines the AWS Parameter Store gateway. It will contain no secret values.

Conceptually:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-parameter-store
spec:
  conditions:
    - namespaces:
        - chad-applications
  provider:
    aws:
      service: ParameterStore
      region: <aws-region>
      role: arn:aws:iam::<account-id>:role/k3s-ssm-parameter-read
      auth:
        jwt:
          serviceAccountRef:
            name: eso-aws-auth
            namespace: external-secrets
```

The namespace condition prevents arbitrary namespaces from using this cluster-scoped store. More namespaces should be added deliberately, not by removing the condition.

## Phase 6: Implement and verify in dependency order

The safe order is:

1. **IaC:** Add or update the k3s service-account issuer configuration with `https://apis.rotorlabs.io/aws-oidc`.
2. **IaC:** Configure public DNS, TLS, Nginx routing, and firewall access for the discovery and JWKS endpoints.
3. **IaC:** Validate the discovery and JWKS endpoints externally.
4. **IaC:** Validate service-account token claims, including issuer, audience, and subject.
5. **IaC:** Create the AWS IAM OIDC provider.
6. **IaC:** Create the ESO authentication role, SSM read role, trust policies, and least-privilege permissions.
7. **GitOps:** Add the pinned ESO Argo `Application` and values.
8. **GitOps:** Add the dedicated service account, restricted token-request RBAC, and any required namespace metadata.
9. **GitOps:** Add the namespace-restricted `ClusterSecretStore`.
10. **Argo CD:** Reconcile ESO and its CRDs before reconciling the store.
11. **IaC/AWS:** Create one non-production test parameter under the approved SSM path.
12. **GitOps/application:** Create one test `ExternalSecret` in the approved namespace.
13. **All:** Verify the generated Kubernetes Secret, ESO status, STS role assumptions, and SSM access logs.
14. **All:** Remove the test resource and parameter according to the selected retention policy.

Do not deploy the `ClusterSecretStore` before the ESO CRDs exist. Do not configure the IAM trust policy before the issuer endpoint and token claims are verified.

## Implementation deliverables

### IaC repository deliverables

- k3s service-account issuer configuration.
- Safe distribution and backup procedure for the service-account signing key.
- Public DNS and TLS configuration for `apis.rotorlabs.io`.
- Exact Nginx routes for the two OIDC endpoints.
- Upstream Kubernetes API TLS validation.
- Firewall rules that permit AWS validation traffic and restrict administrative API access.
- AWS IAM OIDC provider.
- ESO authentication role with subject- and audience-restricted trust.
- SSM read role with path-scoped read permissions.
- Optional customer-managed KMS decrypt permission, only if required.
- Terraform outputs or documented values consumed by GitOps.
- IaC validation and rollback procedure.

### GitOps repository deliverables

- Pinned ESO Helm `Application`.
- Explicit Helm values for CRDs, resources, service-account naming, and security hardening.
- `eso-aws-auth` service account with the authentication role ARN annotation.
- ESO token-request RBAC restricted to that service account.
- Namespace-restricted `ClusterSecretStore`.
- Component README covering prerequisites, dependency order, verification, and rollback.
- No secret values, AWS credentials, signing keys, or generated Secret manifests.

## Acceptance criteria

The implementation is complete only when all of the following are true:

- Argo CD reports the ESO application healthy and synced.
- The ESO CRDs are installed at the pinned version.
- The public discovery document returns the exact issuer URL.
- The public JWKS endpoint is reachable over valid TLS.
- A Kubernetes service-account token has the expected `iss`, `aud`, and `sub` claims.
- AWS accepts `AssumeRoleWithWebIdentity` only for `external-secrets/eso-aws-auth`.
- The authentication role can assume only the SSM read role.
- The SSM read role can read only the approved parameter path.
- The `ClusterSecretStore` reports `Ready=True`.
- An approved namespace can synchronize a test `ExternalSecret`.
- An unapproved namespace cannot use the `ClusterSecretStore`.
- The test application receives the expected Kubernetes Secret.
- CloudTrail shows the expected STS calls and no unexpected SSM write operations.
- No credentials or secret values appear in either repository's Git history or rendered manifests.

## Application-side usage

Application repositories should own their `ExternalSecret` resources. A typical resource will reference the cluster store and explicitly name parameters:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: <application-namespace>
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: database-credentials
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
    - secretKey: username
      remoteRef:
        key: /platform/production/<application>/database/username
    - secretKey: password
      remoteRef:
        key: /platform/production/<application>/database/password
```

Explicit `data` entries are preferred initially. Avoid broad path extraction until the IAM and namespace boundaries are well understood.

## Validation and operational checks

### Kubernetes

Check:

```bash
kubectl get crd externalsecrets.external-secrets.io
kubectl get clustersecretstore aws-parameter-store
kubectl describe clustersecretstore aws-parameter-store
kubectl get externalsecret --all-namespaces
```

The store should report `Ready=True` before application resources reference it.

### AWS

Check:

- CloudTrail records for `AssumeRoleWithWebIdentity`.
- CloudTrail records for `AssumeRole` into the SSM role.
- SSM access limited to the expected parameter ARNs.
- No calls to SSM write or delete APIs.

### Failure diagnosis

If synchronization fails, inspect in this order:

1. `ExternalSecret` status and events.
2. `ClusterSecretStore` status and events.
3. ESO controller logs.
4. The service-account token claims.
5. Nginx access and error logs for the OIDC endpoints.
6. CloudTrail STS events.
7. The IAM trust-policy condition keys and exact issuer path.

## Cost and availability

The OIDC provider and service-account token exchange do not have a separate ongoing AWS charge. Using the existing Nginx and existing certificate should avoid an additional load balancer or EC2 instance.

Potential costs are from:

- Existing or additional DNS hosting.
- Existing Nginx infrastructure.
- Advanced or high-throughput SSM Parameter Store usage.
- Customer-managed KMS keys.
- Network transfer, which should be negligible for discovery and JWKS documents.

The larger concern is availability, not cost. AWS must be able to retrieve the issuer documents when it validates a token. The Nginx endpoint and its DNS must remain available during normal cluster operation and should have a documented recovery path.

## Recovery and rollback

If ESO is removed, application-generated Kubernetes Secrets should not be deleted automatically unless that behavior is explicitly intended. `deletionPolicy: Retain` is the safer starting policy.

If the ESO deployment is rolled back:

- Existing Kubernetes Secrets remain available.
- Refreshes stop until ESO is healthy again.
- AWS IAM roles can remain in place.

If the issuer URL must change:

1. Publish the new discovery and JWKS endpoints.
2. Configure the new issuer in k3s.
3. Create a second AWS IAM OIDC provider.
4. Update trust policies.
5. Verify newly issued tokens.
6. Migrate ESO.
7. Remove the old provider only after all old tokens have expired and the old trust path is unused.

Do not change the issuer path casually.

## Security review checklist

- [ ] OIDC issuer uses the exact permanent URL `https://apis.rotorlabs.io/aws-oidc`.
- [ ] TLS is publicly trusted and does not require client authentication.
- [ ] Only discovery and JWKS endpoints are exposed.
- [ ] The OIDC endpoints bypass application authentication middleware.
- [ ] Kubernetes signing keys are not in Git.
- [ ] IAM trust restricts both `aud` and `sub`.
- [ ] ESO authentication role can assume only the intended SSM role.
- [ ] SSM permissions are limited to the approved path.
- [ ] Customer-managed KMS permissions are limited to the required key.
- [ ] ESO token creation is restricted to `eso-aws-auth`.
- [ ] `ClusterSecretStore` has explicit namespace conditions.
- [ ] Chart and image versions are pinned.
- [ ] No secret values or AWS credentials are present in manifests.
- [ ] Argo destination, project, pruning, and self-healing settings are explicitly reviewed.

## References

- [External Secrets Operator AWS authentication](https://external-secrets.io/latest/provider/aws-access/)
- [External Secrets Operator AWS Parameter Store](https://external-secrets.io/latest/provider/aws-parameter-store/)
- [External Secrets Operator ClusterSecretStore](https://external-secrets.io/latest/api/clustersecretstore/)
- [External Secrets Operator security best practices](https://external-secrets.io/latest/guides/security-best-practices/)
- [Kubernetes service-account issuer discovery](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [AWS IAM OIDC federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
