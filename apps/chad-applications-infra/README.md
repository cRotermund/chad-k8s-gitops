# `chad-applications` Namespace Infrastructure

This Argo CD application owns shared infrastructure for the `chad-applications`
namespace. It does not own application deployments or application-specific
configuration.

## Managed Resources

- Creation of the `chad-applications` namespace through Argo CD's
  `CreateNamespace=true` sync option.
- An ESO `ExternalSecret` named `ghcr-pull-secret`.
- The generated `kubernetes.io/dockerconfigjson` Secret named
  `ghcr-pull-secret`.

The generated Secret is not stored in Git. ESO reads its value from the
`aws-parameter-store` `ClusterSecretStore`, which is restricted to this
namespace.

## AWS SSM Prerequisite

Provision this SSM Parameter Store parameter outside this repository:

```text
/kubernetes/appsecrets/chad-applications/ghcr/dockerconfigjson
```

It must be a `SecureString` containing a complete Docker config JSON document,
for example:

```json
{
  "auths": {
    "ghcr.io": {
      "auth": "<base64-of-github-username-and-pat>"
    }
  }
}
```

Use the GitHub username and the classic PAT when creating the `username:PAT`
value before base64 encoding it. Do not put the PAT, the encoded credential, or
the generated Docker config in Git.

The IAM role referenced by the `aws-parameter-store` ClusterSecretStore must
be allowed to read this parameter. Its current documented scope is
`/kubernetes/appsecrets/*`.

The repository includes `scripts/bootstrap-ghcr-ssm.sh` for Git Bash to create
or replace the parameter with AWS CLI:

```bash
bash ./scripts/bootstrap-ghcr-ssm.sh \
  --github-username '<github-username>' \
  --github-pat '<github-pat>'
```

Passing a PAT as a command-line argument can expose it through shell history or
process inspection. Use a short-lived shell session and remove the command
from history, or adapt the script to obtain the value through a secure prompt
or environment-specific secret mechanism.

## Application Usage

Application repositories should reference the shared Secret explicitly from
their pod templates:

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ghcr-pull-secret
```

The Secret exists only in `chad-applications`; workloads in other namespaces
must use their own pull-secret configuration.

## Verification

Check the namespace, store, and synchronization status without printing the
Secret value:

```bash
kubectl get namespace chad-applications
kubectl get clustersecretstore aws-parameter-store
kubectl get externalsecret ghcr-pull-secret -n chad-applications
kubectl get secret ghcr-pull-secret -n chad-applications \
  -o jsonpath='{.type}{"\n"}'
```

The `ExternalSecret` should report `Ready=True`, and the generated Secret type
should be `kubernetes.io/dockerconfigjson`.
