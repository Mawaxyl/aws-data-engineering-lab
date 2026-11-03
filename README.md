# AWS Data Engineering Lab — CityMove Analytics

Ten projects building one end-to-end data platform for a fictional ride-hailing and
logistics company, covering every domain of the AWS Certified Data Engineer – Associate
(DEA-C01) exam.

Every project ships with: the business problem, an architecture diagram, runnable
infrastructure code, real costs, a security review and a written post-mortem.

**Region:** eu-west-1 (Ireland) · **Target cost:** under $30/month · **Every project ends with teardown.**

| # | Project | Layer | Services | Status |
|---|---|---|---|---|
| [P0](./p0-foundations/) | Foundations: identity and networking | Bronze | IAM, Identity Center, VPC, KMS | 🟡 In progress |
| [P1](./p1-batch-lakehouse/) | Governed lakehouse for NYC taxi trips | Bronze | S3, Glue, Athena, Iceberg, Lake Formation, Redshift, Quick Sight | ⚪ Planned |
| [P2](./p2-kinesis-streaming/) | Real-time rides and fraud alerts | Bronze | Kinesis, Firehose, Managed Flink, Lambda, DynamoDB, OpenSearch | ⚪ Planned |
| [P3](./p3-msk-kafka/) | Kafka on AWS with MSK | Bronze | MSK, MSK Serverless, MSK Connect | ⚪ Planned |
| [P4](./p4-oltp-cdc/) | OLTP to analytics with CDC | Silver | RDS, Aurora, DMS, AppFlow, Snowflake | ⚪ Planned |
| [P5](./p5-emr-spark/) | 80 million trips on EMR and Spark | Silver | EMR, PySpark, Hive, EMRFS, EKS | ⚪ Planned |
| [P6](./p6-orchestration/) | Event-driven orchestration | Silver | Step Functions, MWAA, EventBridge, SQS, Fargate | ⚪ Planned |
| [P7](./p7-observability/) | Observability and audit | Gold | CloudWatch, CloudTrail, Config, Macie | ⚪ Planned |
| [P8](./p8-iac-cicd/) | The lakehouse as code | Gold | CloudFormation, CDK, SAM, CodePipeline | ⚪ Planned |
| [P9](./p9-ml/) | Forecasting demand per zone | Gold | SageMaker AI, Redshift ML | ⚪ Planned |

## Conventions

**Tags on every resource, without exception:**

| Tag | Value |
|---|---|
| `project` | `p0` … `p9` |
| `owner` | `mukthar` |
| `env` | `lab` |

**Credentials:** IAM Identity Center (SSO) only. There are no IAM users and no access
keys in this account. `~/.aws/credentials` does not exist.

**Every project follows the same seven steps:** business problem → architecture diagram →
get the data → build in the console → rebuild with CLI/IaC → test and monitor → teardown
and write it up.

## Writing

Four posts a week, drafted in [`linkedin/`](./linkedin/) and mirrored to
[`blog/`](./blog/):

| Day | Series |
|---|---|
| Monday | AWS Service of the Week |
| Wednesday | Cloud Rosetta (AWS / Azure / GCP) |
| Friday | AI Tools Weekly |
| Sunday | DE Fundamentals |

## Author

Mukthar Datore — preparing for AWS Certified Data Engineer – Associate (DEA-C01).
