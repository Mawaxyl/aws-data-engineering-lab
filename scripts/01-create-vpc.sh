#!/usr/bin/env bash
# 01-create-vpc.sh — Project 0, playbook step 10: build citymove-vpc from the CLI
#
# Creates, in eu-west-1:
#   VPC 10.0.0.0/16 .............. citymove-vpc
#   Internet Gateway
#   2 public subnets  (10.0.1.0/24, 10.0.2.0/24)   in eu-west-1a / 1b
#   2 private subnets (10.0.11.0/24, 10.0.12.0/24) in eu-west-1a / 1b
#   1 public route table  (0.0.0.0/0 -> IGW)
#   1 private route table (no internet route at all)
#   S3 Gateway endpoint on the private route table   <-- free, replaces a ~$33/mo NAT
#   sg-glue  (self-referencing all-TCP, required by Glue)
#   sg-db    (TCP 5432 from sg-glue only)
#   DB subnet group across both private subnets
#
# NO NAT GATEWAY. That is deliberate. Nothing in projects 1-7 needs one.
#
# Everything is tagged project/owner/env so Cost Explorer can group by tag.
# Writes p0-foundations/infra/vpc-outputs.json for later projects to read.
#
# Usage:  source env.sh && bash 01-create-vpc.sh

set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"
PROJECT="p0"
OWNER="${OWNER:-mukthar}"
ENVIRONMENT="${ENVIRONMENT:-lab}"
NAME="citymove"
AZ_A="${REGION}a"
AZ_B="${REGION}b"
OUT_DIR="$(dirname "$0")/../p0-foundations/infra"

TAGS="Key=project,Value=$PROJECT Key=owner,Value=$OWNER Key=env,Value=$ENVIRONMENT"

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    %s\n' "$*"; }

# Helper: tag any resource with the standard three tags plus a Name
tag_it() {
  local id="$1" name="$2"
  aws ec2 create-tags --region "$REGION" --resources "$id" \
    --tags Key=Name,Value="$name" Key=project,Value="$PROJECT" \
           Key=owner,Value="$OWNER" Key=env,Value="$ENVIRONMENT"
}

step "Preflight"
aws sts get-caller-identity --query '[Account,Arn]' --output text \
  || { echo "Not authenticated. Run: aws sso login --profile cm-dev   (or use AWS CloudShell"
       echo "of the console) — it is already signed in as you. This account has no IAM"
       echo "users and no Identity Center, so there is no local profile yet."; exit 1; }
ok "region: $REGION"

# ------------------------------------------------------------------------- VPC
step "Creating VPC 10.0.0.0/16"
VPC_ID=$(aws ec2 create-vpc --region "$REGION" \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$NAME-vpc},{Key=project,Value=$PROJECT},{Key=owner,Value=$OWNER},{Key=env,Value=$ENVIRONMENT}]" \
  --query 'Vpc.VpcId' --output text)
ok "$VPC_ID"

# Required or RDS/MSK/Redshift endpoints will not resolve inside the VPC
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
ok "DNS support and DNS hostnames enabled"

# ------------------------------------------------------------- Internet Gateway
step "Creating and attaching the Internet Gateway"
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$NAME-igw},{Key=project,Value=$PROJECT},{Key=owner,Value=$OWNER},{Key=env,Value=$ENVIRONMENT}]" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --region "$REGION" --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"
ok "$IGW_ID attached"

# --------------------------------------------------------------------- Subnets
# A subnet lives in exactly ONE availability zone. That is the whole reason we
# create four of them: two tiers x two AZs.
make_subnet() {
  local cidr="$1" az="$2" name="$3"
  local id
  id=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" \
        --cidr-block "$cidr" --availability-zone "$az" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name},{Key=project,Value=$PROJECT},{Key=owner,Value=$OWNER},{Key=env,Value=$ENVIRONMENT}]" \
        --query 'Subnet.SubnetId' --output text)
  echo "$id"
}

step "Creating subnets"
PUB_A=$(make_subnet 10.0.1.0/24  "$AZ_A" "$NAME-public-$AZ_A")
PUB_B=$(make_subnet 10.0.2.0/24  "$AZ_B" "$NAME-public-$AZ_B")
PRIV_A=$(make_subnet 10.0.11.0/24 "$AZ_A" "$NAME-private-$AZ_A")
PRIV_B=$(make_subnet 10.0.12.0/24 "$AZ_B" "$NAME-private-$AZ_B")
ok "public:  $PUB_A ($AZ_A)  $PUB_B ($AZ_B)"
ok "private: $PRIV_A ($AZ_A)  $PRIV_B ($AZ_B)"

# Public subnets auto-assign a public IP; private ones must not
for s in "$PUB_A" "$PUB_B"; do
  aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$s" --map-public-ip-on-launch
done
ok "auto-assign public IPv4 enabled on the public subnets only"

# ----------------------------------------------------------------- Route tables
# This is the lesson of Project 0: there is no "public subnet" checkbox.
# A subnet is public if and only if its route table has 0.0.0.0/0 -> igw-...
step "Creating route tables"

RTB_PUB=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$NAME-rtb-public},{Key=project,Value=$PROJECT},{Key=owner,Value=$OWNER},{Key=env,Value=$ENVIRONMENT}]" \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route --region "$REGION" --route-table-id "$RTB_PUB" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
ok "$RTB_PUB  (0.0.0.0/0 -> $IGW_ID)  <- this line makes a subnet public"

aws ec2 associate-route-table --region "$REGION" --route-table-id "$RTB_PUB" --subnet-id "$PUB_A" >/dev/null
aws ec2 associate-route-table --region "$REGION" --route-table-id "$RTB_PUB" --subnet-id "$PUB_B" >/dev/null

RTB_PRIV=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$NAME-rtb-private},{Key=project,Value=$PROJECT},{Key=owner,Value=$OWNER},{Key=env,Value=$ENVIRONMENT}]" \
  --query 'RouteTable.RouteTableId' --output text)
ok "$RTB_PRIV  (local only - no 0.0.0.0/0, no NAT Gateway)"

aws ec2 associate-route-table --region "$REGION" --route-table-id "$RTB_PRIV" --subnet-id "$PRIV_A" >/dev/null
aws ec2 associate-route-table --region "$REGION" --route-table-id "$RTB_PRIV" --subnet-id "$PRIV_B" >/dev/null

# ------------------------------------------------------------- S3 Gateway endpoint
# Free. Adds a prefix-list route so private subnets reach S3 privately.
# Without this, a Glue job in a private subnet cannot even download its own
# libraries, and hangs for ~15 minutes before timing out.
step "Creating the S3 Gateway endpoint (free - this is instead of a NAT Gateway)"
VPCE_S3=$(aws ec2 create-vpc-endpoint --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --service-name "com.amazonaws.${REGION}.s3" \
  --vpc-endpoint-type Gateway \
  --route-table-ids "$RTB_PRIV" "$RTB_PUB" \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$NAME-vpce-s3},{Key=project,Value=$PROJECT},{Key=owner,Value=$OWNER},{Key=env,Value=$ENVIRONMENT}]" \
  --query 'VpcEndpoint.VpcEndpointId' --output text)
ok "$VPCE_S3"

# A DynamoDB gateway endpoint is also free and Project 2 will want it
VPCE_DDB=$(aws ec2 create-vpc-endpoint --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --service-name "com.amazonaws.${REGION}.dynamodb" \
  --vpc-endpoint-type Gateway \
  --route-table-ids "$RTB_PRIV" \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$NAME-vpce-dynamodb},{Key=project,Value=$PROJECT},{Key=owner,Value=$OWNER},{Key=env,Value=$ENVIRONMENT}]" \
  --query 'VpcEndpoint.VpcEndpointId' --output text)
ok "$VPCE_DDB  (DynamoDB, also free - Project 2 needs it)"

# ------------------------------------------------------------- Security groups
step "Creating security groups"

# sg-glue: Glue's Spark driver and executors talk to each other across ENIs in
# your subnet, so the group MUST allow all TCP from itself. Omit this and your
# first Glue-in-VPC job hangs and then fails with a timeout that explains nothing.
SG_GLUE=$(aws ec2 create-security-group --region "$REGION" \
  --group-name "$NAME-sg-glue" \
  --description "Glue/EMR connection SG - self-referencing all-TCP is required by Glue" \
  --vpc-id "$VPC_ID" --query 'GroupId' --output text)
tag_it "$SG_GLUE" "$NAME-sg-glue"

aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_GLUE" \
  --ip-permissions "IpProtocol=tcp,FromPort=0,ToPort=65535,UserIdGroupPairs=[{GroupId=$SG_GLUE,Description=\"Glue requires a self-referencing rule\"}]" >/dev/null
ok "$SG_GLUE  sg-glue  (all TCP from itself)"

# sg-db: reference the Glue security group, never an IP range. If the Glue ENIs
# move or the subnet changes, this rule keeps working.
SG_DB=$(aws ec2 create-security-group --region "$REGION" \
  --group-name "$NAME-sg-db" \
  --description "Postgres 5432 - only from the Glue SG" \
  --vpc-id "$VPC_ID" --query 'GroupId' --output text)
tag_it "$SG_DB" "$NAME-sg-db"

aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_DB" \
  --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=$SG_GLUE,Description=\"Postgres from Glue only\"}]" >/dev/null
ok "$SG_DB  sg-db  (5432 from sg-glue only)"

# Project 3 will need Kafka IAM auth on 9098; add it now so the VPC is ready
SG_KAFKA=$(aws ec2 create-security-group --region "$REGION" \
  --group-name "$NAME-sg-kafka-client" \
  --description "MSK client - 9098 (IAM auth) from this group" \
  --vpc-id "$VPC_ID" --query 'GroupId' --output text)
tag_it "$SG_KAFKA" "$NAME-sg-kafka-client"
aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_KAFKA" \
  --ip-permissions "IpProtocol=tcp,FromPort=9098,ToPort=9098,UserIdGroupPairs=[{GroupId=$SG_KAFKA,Description=\"MSK IAM auth\"}]" >/dev/null
ok "$SG_KAFKA  sg-kafka-client  (9098 from itself - for Project 3)"

# ------------------------------------------------------------- DB subnet group
step "Creating the RDS DB subnet group (Project 4 needs it)"
aws rds create-db-subnet-group --region "$REGION" \
  --db-subnet-group-name "$NAME-db-subnets" \
  --db-subnet-group-description "CityMove private subnets for RDS/Aurora" \
  --subnet-ids "$PRIV_A" "$PRIV_B" \
  --tags "Key=project,Value=$PROJECT" "Key=owner,Value=$OWNER" "Key=env,Value=$ENVIRONMENT" \
  >/dev/null
ok "$NAME-db-subnets"

# ----------------------------------------------------------------- Save outputs
mkdir -p "$OUT_DIR"
cat > "$OUT_DIR/vpc-outputs.json" <<EOF
{
  "region": "$REGION",
  "vpc_id": "$VPC_ID",
  "igw_id": "$IGW_ID",
  "subnets": {
    "public":  { "$AZ_A": "$PUB_A",  "$AZ_B": "$PUB_B" },
    "private": { "$AZ_A": "$PRIV_A", "$AZ_B": "$PRIV_B" }
  },
  "route_tables": { "public": "$RTB_PUB", "private": "$RTB_PRIV" },
  "vpc_endpoints": { "s3": "$VPCE_S3", "dynamodb": "$VPCE_DDB" },
  "security_groups": { "glue": "$SG_GLUE", "db": "$SG_DB", "kafka_client": "$SG_KAFKA" },
  "db_subnet_group": "$NAME-db-subnets",
  "nat_gateway": null
}
EOF

cat <<EOF

==> Done. Outputs written to $OUT_DIR/vpc-outputs.json

    VPC            $VPC_ID
    public  RTB    $RTB_PUB   -> 0.0.0.0/0 via $IGW_ID
    private RTB    $RTB_PRIV  -> local + S3/DynamoDB prefix lists only
    NAT Gateway    none (saves ~\$33/month)

    Monthly cost of everything above: \$0.00

Now run:  bash 02-verify.sh
EOF
