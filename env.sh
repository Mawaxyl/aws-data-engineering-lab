#!/usr/bin/env bash
# source env.sh   — shared settings for every project in this lab

# Primary account: citymove-platform (825100876987), eu-west-1 (Ireland).
export AWS_REGION="eu-west-1"
export AWS_DEFAULT_REGION="eu-west-1"

# Credentials come from IAM Identity Center (SSO) — no access keys anywhere.
# Set up once with:  aws configure sso --profile cm-dev
# When a command fails with "Token has expired": aws sso login --profile cm-dev
export AWS_PROFILE="${AWS_PROFILE:-cm-dev}"

# Sandbox account: citymove-lab (715489363765), eu-north-1, SCP-restricted,
# holds $200 of credits. To work there instead:
#   export AWS_PROFILE=cm-lab AWS_REGION=eu-north-1

export OWNER="mukthar"
export ENVIRONMENT="lab"
export ORG="citymove"

ACCT="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
export ACCT

if [[ -z "$ACCT" ]]; then
  echo "!! Not authenticated."
  echo "   Run: aws sso login --profile cm-dev"
  echo "   If you have not set SSO up yet, see step 5 of P0-START-HERE.md"
else
  echo "account=$ACCT  region=$AWS_REGION  profile=${AWS_PROFILE:-<none>}"
fi
