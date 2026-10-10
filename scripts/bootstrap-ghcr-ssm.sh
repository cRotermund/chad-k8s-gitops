#!/usr/bin/env bash

set -euo pipefail

parameter_name='/kubernetes/appsecrets/chad-applications/ghcr/dockerconfigjson'
aws_region='us-east-1'
aws_profile=''
github_username=''
github_pat=''

usage() {
  cat <<'EOF'
Usage:
  bootstrap-ghcr-ssm.sh --github-username USERNAME --github-pat PAT [options]

Options:
  --github-username USERNAME  GitHub username used for GHCR authentication
  --github-pat PAT            GitHub classic PAT with package read access
  --aws-region REGION         AWS region (default: us-east-1)
  --parameter-name NAME       SSM parameter name
                              (default: /kubernetes/appsecrets/chad-applications/ghcr/dockerconfigjson)
  --aws-profile PROFILE       Optional AWS CLI profile
  -h, --help                  Show this help
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_single_line() {
  local name=$1
  local value=$2

  [[ -n "$value" ]] || fail "$name must not be empty."
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || fail "$name must not contain newline characters."
}

while (($# > 0)); do
  case "$1" in
    --github-username)
      (($# >= 2)) || fail '--github-username requires a value.'
      github_username=$2
      shift 2
      ;;
    --github-pat|--github-token|--pat|--token)
      (($# >= 2)) || fail "$1 requires a value."
      github_pat=$2
      shift 2
      ;;
    --aws-region)
      (($# >= 2)) || fail '--aws-region requires a value.'
      aws_region=$2
      shift 2
      ;;
    --parameter-name)
      (($# >= 2)) || fail '--parameter-name requires a value.'
      parameter_name=$2
      shift 2
      ;;
    --aws-profile)
      (($# >= 2)) || fail '--aws-profile requires a value.'
      aws_profile=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

require_single_line 'GitHub username' "$github_username"
require_single_line 'GitHub PAT/token' "$github_pat"
require_single_line 'AWS region' "$aws_region"
require_single_line 'SSM parameter name' "$parameter_name"
if [[ -n "$aws_profile" ]]; then
  require_single_line 'AWS profile' "$aws_profile"
fi

command -v aws >/dev/null 2>&1 || fail 'AWS CLI was not found in PATH. Install AWS CLI and try again.'
command -v base64 >/dev/null 2>&1 || fail 'base64 was not found in PATH.'

# Passing a PAT as a command-line argument can expose it in shell or process
# history. Prefer a prompt or environment-specific secret mechanism when practical.
auth=$(printf '%s:%s' "$github_username" "$github_pat" | base64 | tr -d '\r\n')
docker_config=$(printf '{"auths":{"ghcr.io":{"auth":"%s"}}}' "$auth")

aws_args=(
  ssm put-parameter
  --name "$parameter_name"
  --type SecureString
  --value "$docker_config"
  --overwrite
  --region "$aws_region"
  --query Version
  --output text
)
if [[ -n "$aws_profile" ]]; then
  aws_args+=(--profile "$aws_profile")
fi

# Capture the response so AWS can explain failures such as missing credentials or
# insufficient SSM/KMS permissions. Redact every value derived from the PAT
# before displaying an error.
# Git Bash can rewrite POSIX-looking arguments such as /kubernetes/... into
# Windows paths before invoking a native AWS CLI executable. Keep the SSM name
# unchanged when crossing that boundary.
if ! aws_output=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' aws "${aws_args[@]}" 2>&1); then
  safe_error=${aws_output//"$docker_config"/'[REDACTED_DOCKER_CONFIG]'}
  safe_error=${safe_error//"$auth"/'[REDACTED_AUTH]'}
  safe_error=${safe_error//"$github_pat"/'[REDACTED_PAT]'}
  printf 'AWS SSM put-parameter failed:\n%s\n' "$safe_error" >&2
  exit 1
fi
version=$aws_output
[[ "$version" =~ ^[0-9]+$ ]] || fail 'AWS SSM put-parameter succeeded, but its version could not be read safely.'

printf 'ParameterName: %s\n' "$parameter_name"
printf 'Version: %s\n' "$version"
printf 'Region: %s\n' "$aws_region"
