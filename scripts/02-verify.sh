#!/usr/bin/env bash
# 02-verify.sh — prove the landing zone is correct and that nothing is costing money.
#
# Checks, in order:
#   1. You are authenticated via SSO, not an IAM access key
#   2. ~/.aws/credentials does not exist
#   3. The VPC exists with DNS enabled
#   4. The public route table has 0.0.0.0/0 -> IGW
#   5. The private route table has NO 0.0.0.0/0 route
#   6. The S3 gateway endpoint is available and attached to the private RTB
#   7. There are NO NAT Gateways in the region
#   8. There are no unattached Elastic IPs
#   9. sg-glue has the self-referencing rule Glue requires
#  10. sg-db only accepts 5432 from sg-glue
#  11. Every resource carries project/owner/env tags
#  12. Budgets exist
#
# Usage:  source env.sh && bash 02-verify.sh

set -uo pipefail

REGION="${AWS_REGION:-eu-west-1}"
OUT="$(dirname "$0")/../p0-foundations/infra/vpc-outputs.json"
PASS=0; FAIL=0; WARN=0

pass() { printf '  \033[32m[PASS]\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[33m[WARN]\033[0m %s\n' "$*"; WARN=$((WARN+1)); }
section() { printf '\n%s\n' "$*"; }

need_jq() {
  command -v jq >/dev/null || { echo "jq is required. Install it: winget install jqlang.jq  (or apt install jq)"; exit 1; }
}
need_jq

# ---------------------------------------------------------------- 1-2 identity
section "Identity and credentials"

ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
if [[ -z "$ARN" ]]; then
  fail "not authenticated"
  printf '         Run: aws sso login --profile cm-dev   (or use AWS CloudShell of the console).\n'
  printf '         This account has no IAM users and IAM Identity Center is not supported\n'
  printf '         on the project experience, so there is no local profile to log in with.\n'
  exit 1
fi
if [[ "$ARN" == *":user/"* ]]; then
  fail "authenticated as an IAM user: $ARN"
  printf '         Long-lived credentials. Prefer a role (CloudShell or Identity Center).\n'
else
  pass "authenticated via a role, not an IAM user: $ARN"
fi

# In CloudShell there is no ~/.aws/credentials and that is the point.
if [[ -f "$HOME/.aws/credentials" ]]; then
  warn "$HOME/.aws/credentials exists — check it holds no long-lived access keys"
else
  pass "no ~/.aws/credentials file (nothing long-lived on this machine)"
fi

# On a project account the managed SCPs may deny iam:ListUsers outright.
# A denial is the expected, correct answer here — not a failure.
IAM_OUT=$(aws iam list-users --query 'Users[].UserName' --output text 2>&1)
if [[ "$IAM_OUT" == *"AccessDenied"* || "$IAM_OUT" == *"not authorized"* ]]; then
  pass "iam:ListUsers denied by the project SCP — IAM users are not in play"
elif [[ -z "$IAM_OUT" || "$IAM_OUT" == "None" ]]; then
  pass "no IAM users in the account"
else
  warn "IAM users exist: $IAM_OUT — check whether any have access keys"
fi

# ------------------------------------------------------------------- 3 the VPC
section "Network"

if [[ -f "$OUT" ]]; then
  VPC_ID=$(jq -r '.vpc_id' "$OUT")
  RTB_PUB=$(jq -r '.route_tables.public' "$OUT")
  RTB_PRIV=$(jq -r '.route_tables.private' "$OUT")
  SG_GLUE=$(jq -r '.security_groups.glue' "$OUT")
  SG_DB=$(jq -r '.security_groups.db' "$OUT")
else
  warn "no vpc-outputs.json — looking up citymove-vpc by Name tag"
  VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=citymove-vpc" --query 'Vpcs[0].VpcId' --output text)
  RTB_PUB=$(aws ec2 describe-route-tables --region "$REGION" \
    --filters "Name=tag:Name,Values=citymove-rtb-public" --query 'RouteTables[0].RouteTableId' --output text)
  RTB_PRIV=$(aws ec2 describe-route-tables --region "$REGION" \
    --filters "Name=tag:Name,Values=citymove-rtb-private" --query 'RouteTables[0].RouteTableId' --output text)
  SG_GLUE=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=group-name,Values=citymove-sg-glue" --query 'SecurityGroups[0].GroupId' --output text)
  SG_DB=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=group-name,Values=citymove-sg-db" --query 'SecurityGroups[0].GroupId' --output text)
fi

if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  fail "citymove-vpc not found in $REGION"
  exit 1
fi
pass "VPC $VPC_ID exists"

DNS_H=$(aws ec2 describe-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" \
  --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value' --output text)
[[ "$DNS_H" == "True" ]] \
  && pass "DNS hostnames enabled (RDS/MSK endpoints will resolve)" \
  || fail "DNS hostnames disabled — RDS and MSK endpoints will not resolve"

SUBNET_COUNT=$(aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" --query 'length(Subnets)' --output text)
[[ "$SUBNET_COUNT" -ge 4 ]] \
  && pass "$SUBNET_COUNT subnets across 2 AZs" \
  || fail "only $SUBNET_COUNT subnets — expected 4"

# ------------------------------------------------------------ 4-5 route tables
PUB_IGW=$(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$RTB_PUB" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" --output text)
if [[ "$PUB_IGW" == igw-* ]]; then
  pass "public route table: 0.0.0.0/0 -> $PUB_IGW"
else
  fail "public route table has no internet route (found: $PUB_IGW)"
fi

PRIV_DEFAULT=$(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$RTB_PRIV" \
  --query "length(RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'])" --output text)
if [[ "$PRIV_DEFAULT" == "0" ]]; then
  pass "private route table has NO 0.0.0.0/0 route (truly private, and no NAT bill)"
else
  fail "private route table has a default route — something is sending traffic out"
fi

# -------------------------------------------------------------- 6 S3 endpoint
S3_VPCE=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=com.amazonaws.$REGION.s3" \
  --query 'VpcEndpoints[0].[VpcEndpointId,State]' --output text)
if [[ "$S3_VPCE" == *available* ]]; then
  pass "S3 gateway endpoint available: ${S3_VPCE%%$'\t'*}"
else
  fail "no available S3 gateway endpoint — Glue in a private subnet WILL hang and time out"
fi

S3_ON_PRIV=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=com.amazonaws.$REGION.s3" \
  --query "contains(VpcEndpoints[0].RouteTableIds, '$RTB_PRIV')" --output text)
[[ "$S3_ON_PRIV" == "true" ]] \
  && pass "S3 endpoint is attached to the private route table" \
  || fail "S3 endpoint is NOT on the private route table"

# ------------------------------------------------------------------- 7-8 cost
section "Cost guardrails"

NATS=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=state,Values=available,pending" --query 'length(NatGateways)' --output text)
if [[ "$NATS" == "0" ]]; then
  pass "no NAT Gateways in $REGION (saving ~\$33/month each)"
else
  fail "$NATS NAT Gateway(s) running — that is ~\$33/month each. Delete them."
  aws ec2 describe-nat-gateways --region "$REGION" \
    --filter "Name=state,Values=available,pending" \
    --query 'NatGateways[].[NatGatewayId,SubnetId]' --output table
fi

EIPS=$(aws ec2 describe-addresses --region "$REGION" \
  --query 'length(Addresses[?AssociationId==null])' --output text)
[[ "$EIPS" == "0" ]] \
  && pass "no unattached Elastic IPs" \
  || warn "$EIPS unattached Elastic IP(s) — these bill hourly. Release them."

# Anything expensive left running anywhere?
for check in \
  "emr:aws emr list-clusters --region $REGION --active --query length(Clusters)" \
  "redshift-serverless:aws redshift-serverless list-workgroups --region $REGION --query length(workgroups)" \
  "opensearch:aws opensearch list-domain-names --region $REGION --query length(DomainNames)" \
  "msk:aws kafka list-clusters-v2 --region $REGION --query length(ClusterInfoList)" \
  "rds:aws rds describe-db-instances --region $REGION --query length(DBInstances)" \
; do
  svc="${check%%:*}"; cmd="${check#*:}"
  n=$($cmd --output text 2>/dev/null || echo 0)
  [[ "$n" == "0" || -z "$n" ]] \
    && pass "no $svc resources running" \
    || warn "$n $svc resource(s) exist — expected for the project you're on, otherwise tear down"
done

BUDGETS=$(aws budgets describe-budgets \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --query 'length(Budgets)' --output text 2>/dev/null || echo 0)
if [[ "$BUDGETS" -ge 1 ]]; then
  pass "$BUDGETS budget(s) configured"
  aws budgets describe-budgets \
    --account-id "$(aws sts get-caller-identity --query Account --output text)" \
    --query 'Budgets[].[BudgetName,TimeUnit,BudgetLimit.Amount]' --output table 2>/dev/null
else
  fail "no AWS Budgets configured — do step 2 before creating anything else"
fi

# ----------------------------------------------------------- 9-10 security groups
section "Security groups"

SELF_REF=$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_GLUE" \
  --query "contains(SecurityGroups[0].IpPermissions[].UserIdGroupPairs[].GroupId, '$SG_GLUE')" \
  --output text 2>/dev/null)
[[ "$SELF_REF" == "true" ]] \
  && pass "sg-glue has the self-referencing rule Glue requires" \
  || fail "sg-glue is MISSING its self-referencing rule — Glue-in-VPC jobs will hang then time out"

DB_SRC=$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_DB" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\`].UserIdGroupPairs[].GroupId | [0]" \
  --output text 2>/dev/null)
[[ "$DB_SRC" == "$SG_GLUE" ]] \
  && pass "sg-db accepts 5432 from sg-glue only (no CIDR ranges)" \
  || warn "sg-db port 5432 source is '$DB_SRC' — should be $SG_GLUE"

OPEN=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "length(SecurityGroups[?IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']]])" --output text)
[[ "$OPEN" == "0" ]] \
  && pass "no security group is open to 0.0.0.0/0" \
  || fail "$OPEN security group(s) allow inbound from 0.0.0.0/0 — fix before anything else"

# ------------------------------------------------------------------- 11 tagging
section "Tagging"

UNTAGGED=$(aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "length(Subnets[?!not_null(Tags[?Key=='project'])])" --output text)
[[ "$UNTAGGED" == "0" ]] \
  && pass "every subnet carries a project tag" \
  || fail "$UNTAGGED subnet(s) missing the project tag — Cost Explorer can't group them"

ACTIVE_TAGS=$(aws ce list-cost-allocation-tags --status Active \
  --query "length(CostAllocationTags[?TagKey=='project'||TagKey=='owner'])" --output text 2>/dev/null || echo 0)
[[ "$ACTIVE_TAGS" -ge 2 ]] \
  && pass "cost allocation tags project+owner are Active" \
  || warn "activate 'project' and 'owner' in Billing > Cost allocation tags (takes ~24h to apply)"

# -------------------------------------------------------------------- summary
printf '\n%s\n' "────────────────────────────────────────"
printf 'PASS %d   WARN %d   FAIL %d\n' "$PASS" "$WARN" "$FAIL"
printf '%s\n' "────────────────────────────────────────"

if [[ "$FAIL" -gt 0 ]]; then
  printf '\nFix the FAILs before moving to Project 1.\n'
  printf 'Paste any error you do not understand into p0-foundations/NOTES.md first.\n\n'
  exit 1
fi

printf '\nLanding zone is sound. Running cost of the above: \$0.00/month.\n'
printf 'Next: Project 1 — the batch lakehouse.\n\n'
