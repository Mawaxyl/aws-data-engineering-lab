# AWS Networking Primer
### VPCs, subnets, route tables and security groups — and how to design them

> Written while building Project 0 of the CityMove Analytics lab, November 2026.
> Reference document: read it once to understand, come back to Part 3 when designing.

**Contents**

- [Part 1 — The concepts](#part-1)
- [Part 2 — Applied to CityMove](#part-2)
- [Part 3 — A design framework](#part-3)
- [Part 4 — Exam quick reference](#part-4)

---

<a name="part-1"></a>
## Part 1 — The concepts, in the order they make sense

### 1.1 VPC — your own private network

AWS runs millions of customers' machines in the same data centres. A **VPC (Virtual Private Cloud)** is your private, isolated slice of that network. Nothing enters or leaves unless you explicitly allow it.

A VPC lives in **one region** and can span the Availability Zones within it.

```
citymove-vpc    10.0.0.0/16    eu-west-1
```

That's ~65,000 private IP addresses that exist only inside your VPC.

### 1.2 CIDR — reading address ranges

`10.0.0.0/16` means: *"addresses beginning 10.0, anything after that."*

An IPv4 address is 32 bits — four numbers of 8 bits each. The `/16` says **the first 16 bits are fixed**:

```
  10  .  0  .  0  .  0     /16
  └────┬────┘ └────┬────┘
    fixed       free
```

So the range runs `10.0.0.0` → `10.0.255.255`.

**Smaller number = bigger range:**

| CIDR | Addresses | Typical use |
|---|---|---|
| `/16` | 65,536 | A whole VPC |
| `/20` | 4,096 | A subnet (AWS wizard default) |
| `/24` | 256 | A subnet (tidy, human-readable) |
| `/32` | 1 | One specific host |

And **`0.0.0.0/0` fixes zero bits — every possible address.** That's why it means "the entire internet" in a route table.

**AWS reserves 5 addresses in every subnet** (network address, VPC router, DNS, future use, broadcast). A `/24` gives you 251 usable, not 256.

### 1.3 Subnets — slices pinned to one data centre

A **subnet** is a smaller range carved from the VPC.

> **A subnet exists in exactly one Availability Zone and cannot span two.**

An **AZ** is a physically separate data centre with independent power, cooling and networking, a few kilometres from its siblings, linked by private fibre at under 2ms.

Choosing a subnet means choosing which physical building your resource sits in. **That's why you build two of everything** — if `eu-west-1a` fails, `eu-west-1b` carries on.

```
10.0.0.0/20     public    eu-west-1a
10.0.16.0/20    public    eu-west-1b
10.0.128.0/20   private   eu-west-1a
10.0.144.0/20   private   eu-west-1b
```

> **Gotcha:** AZ names are randomised per account. Your `eu-west-1a` is not someone else's. Use **AZ IDs** (`euw1-az1`) when it matters across accounts.

### 1.4 Internet Gateway — the door to the street

An **IGW** attaches to the VPC. It is the only path between your VPC and the internet. Horizontally scaled, highly available, free.

Attaching one makes nothing public. It means the door now exists. Whether a subnet *uses* it is decided by its route table.

### 1.5 Route tables — the signpost

Every subnet has a route table. When something in that subnet sends a packet, the table answers one question:

> *"This packet is addressed to X. Which way do I send it?"*

A list of destinations and directions. **Longest prefix match wins** — the most specific rule applies.

**Public route table:**
```
10.0.0.0/16   →  local        inside the VPC, deliver locally
0.0.0.0/0     →  igw-xxxxx    everything else, out the front door
```

**Private route table:**
```
10.0.0.0/16   →  local        inside the VPC, deliver locally
pl-6da54004   →  vpce-xxxxx   that's S3, use the private endpoint
```

`local` is always present and cannot be removed — it's why subnets in the same VPC can talk without configuration.

`pl-xxxxxxxx` is a **prefix list**: an AWS-managed list of all IP ranges for a service in that region, kept up to date by AWS.

### 1.6 Public vs private is only this

> **A subnet is public if and only if its route table contains `0.0.0.0/0 → igw-xxxxx`.**

There is no "public" checkbox in AWS. There is only that line.

A private subnet doesn't have it, so its resources have **no route to the internet**. Not firewalled — they simply have no way out. That's a stronger guarantee than a rule, because there's nothing to misconfigure.

> **A route table does nothing until a subnet is associated with it.** An unassociated subnet silently falls back to the VPC's **Main** route table. Always check the "Explicit subnet associations" count, not just the routes.

### 1.7 VPC endpoints — a private door to one AWS service

Private subnets have no internet route. But a Glue job there still needs S3 — for its script, its libraries, its data.

**Two ways to solve it:**

| | NAT Gateway | VPC Endpoint |
|---|---|---|
| What | A device in a public subnet that lets private resources reach out (never in) | A private path to one specific AWS service |
| Reaches | Anything on the internet | Only that service |
| Traffic path | Out to the internet and back | Stays on AWS's internal network |
| **Cost** | **~$33/month each + data** | **Gateway: free.** Interface: ~$7/month |

**Two kinds of endpoint:**

- **Gateway endpoint** — S3 and DynamoDB only. Works by adding a route-table entry. **Free.** Always add these.
- **Interface endpoint (PrivateLink)** — an ENI with a private IP in your subnet, for nearly every other service (Secrets Manager, KMS, Kinesis, Glue API, CloudWatch Logs). Costs per hour, so add only what you need.

### 1.8 Security groups — the door policy

Route tables decide **where traffic may go**. Security groups decide **what may enter or leave a specific resource**. Two separate layers; you need both.

A security group attaches to an **ENI (Elastic Network Interface)** — the virtual network card on an EC2 instance, an RDS database, a Lambda in a VPC, a Glue job.

**Three properties that matter:**

**Stateful.** Allow traffic in and the reply is automatically allowed out. You never write return rules.

**Allow-only.** There is no deny rule. Anything not explicitly allowed is blocked.

**They can reference each other.** A rule's source can be *another security group* rather than an IP range. This is the feature that makes them genuinely good, and it's covered in Part 2.

### 1.9 NACLs — the other firewall

| | Security Group | Network ACL |
|---|---|---|
| Attaches to | An ENI (one resource) | A subnet (everything in it) |
| State | **Stateful** — replies auto-allowed | **Stateless** — you must allow return traffic too |
| Rules | Allow only | Allow **and** Deny |
| Evaluation | All rules considered | Numbered order, first match wins |
| Default | Deny all in, allow all out | Allow everything both ways |

**Leave NACLs at default.** They exist for coarse blocks — banning an IP range at the subnet edge. Being stateless, they're easy to break: forget the ephemeral return ports (1024–65535) and everything stops working for reasons that are hard to see.

Use security groups for almost everything.

---

<a name="part-2"></a>
## Part 2 — Applied to CityMove

### 2.1 The layout

```
┌───────────────── citymove-vpc  10.0.0.0/16  (eu-west-1) ─────────────────┐
│                                                                           │
│  PUBLIC SUBNETS            route: 0.0.0.0/0 → IGW                        │
│  ┌───────────────────┐     ┌───────────────────┐                         │
│  │    eu-west-1a     │     │    eu-west-1b     │   ← empty, by design     │
│  └───────────────────┘     └───────────────────┘                         │
│                                                                           │
│  PRIVATE SUBNETS           route: S3 prefix list → gateway endpoint       │
│  ┌───────────────────┐     ┌───────────────────┐                         │
│  │    eu-west-1a     │     │    eu-west-1b     │                         │
│  │  • Glue ENIs      │     │  • Glue ENIs      │   [sg-glue]             │
│  │  • RDS Postgres   │     │  • RDS standby    │   [sg-db]               │
│  │  • EMR nodes      │     │                   │                         │
│  │  • MSK brokers    │     │  • MSK brokers    │                         │
│  └───────────────────┘     └───────────────────┘                         │
│                                     │                                     │
└─────────────────────────────────────┼─────────────────────────────────────┘
                                      │  S3 Gateway Endpoint (free)
                                      ↓
                                 Amazon S3
```

**Everything that stores or processes data sits in private subnets.** None of it should ever be reachable from the internet.

**The public subnets are empty, and that is correct.** They exist for things that must face the internet — a load balancer, a NAT gateway if one is ever needed, a bastion host. A data platform mostly doesn't need any of those.

### 2.2 Why Glue needs a self-referencing rule

When a Glue job uses a **Glue Connection** to reach something in your VPC, Glue creates **ENIs** inside your private subnet. They take private IPs from your range.

A Spark job is not one process. It's a **driver** plus several **executors**, each on its own ENI:

```
   ENI (driver)    10.0.128.45
        ↕  ↕  ↕                    ← constant traffic on dynamic high ports
   ENI (executor)  10.0.128.67
   ENI (executor)  10.0.128.89
   ENI (executor)  10.0.129.12
```

The driver assigns tasks, executors report back, and they shuffle data between themselves — all on dynamically assigned ports you cannot know in advance.

Every one of those ENIs carries `citymove-sg-glue`. So the rule:

```
Type:   All TCP
Source: citymove-sg-glue        (itself)
```

reads as: **"anything wearing this badge may talk to anything else wearing this badge, on any port."**

**Without it:** the job launches, executors can't reach the driver, and it hangs for roughly fifteen minutes before dying with a timeout that says nothing about networking. One of the most common Glue-in-VPC failures.

**The general principle:** any distributed compute whose members talk to each other needs a self-referencing rule. Spark on Glue, MSK brokers, OpenSearch nodes, EMR.

> **EMR footnote:** EMR creates and manages its own self-referencing security groups automatically — you rarely build them by hand. The reason is identical, and knowing it means you'll read EMR's generated SGs with understanding rather than treating them as magic.

### 2.3 Why `sg-db` references `sg-glue`

Project 4's flow: a Glue job reads from RDS Postgres.

```
   Glue ENI   ───── TCP 5432 ─────>   RDS Postgres
   [sg-glue]                          [sg-db]
```

The rule on `sg-db`:

```
Type:   PostgreSQL (5432)
Source: citymove-sg-glue
```

**"Anything carrying the Glue badge may reach Postgres on 5432."**

**Why not an IP range?** Glue's ENIs get new IPs on every run.

- Allow one IP → broken tomorrow.
- Allow the subnet CIDR → Postgres is now open to *everything* in that subnet, including whatever you add next year.
- Allow the **security group** → correct forever. Ten more Glue jobs work automatically because they wear the same badge. Anything else in that subnet gets nothing, because it doesn't.

**This is the pattern for every service-to-service rule you will ever write.** Lambda → RDS. EMR → MSK. Redshift → Aurora. Always group-to-group.

### 2.4 Why the S3 endpoint is mandatory, not optional

Before a Glue job runs a single line of your code it fetches:

1. Your script, from S3
2. Any extra Python modules or JARs, from S3
3. Then your actual data, from S3

In a private subnet with no internet route **and no S3 endpoint, all three fail.** The job hangs, then times out.

That's why the endpoint is a required part of a data-platform VPC — and why it's free is the happy accident.

### 2.5 Why no NAT Gateway

Nothing in this platform needs to reach the open internet.

- S3 and DynamoDB → gateway endpoints, free
- Everything else AWS → interface endpoints if genuinely needed
- Third-party APIs (e.g. a weather API in Project 3) → run that bit from Lambda outside the VPC, or accept one NAT for a single afternoon and delete it

**A NAT Gateway costs ~$33/month and does nothing while idle.** In a three-AZ production setup that's ~$100/month before a single workload runs. It is the largest avoidable line item in most learning accounts.

---

<a name="part-3"></a>
## Part 3 — A design framework

Five questions, in this order, for any VPC you design or review.

### 1. What genuinely needs to be reachable *from* the internet?

Usually almost nothing. A load balancer. Maybe an API Gateway.

**Never a database. Never a processing job. Never a message broker.**

Everything else → private subnets.

### 2. What needs to reach *out*, and can an endpoint replace it?

List what your private resources must call:

| Need | Solution | Cost |
|---|---|---|
| S3, DynamoDB | Gateway endpoint | **Free** |
| Secrets Manager, KMS, Kinesis, Glue API, CloudWatch Logs, STS | Interface endpoint | ~$7/mo each |
| Genuine third-party internet | NAT Gateway | ~$33/mo + data |

Reach for NAT **last**, not first. Most data platforms need none.

### 3. What talks to what, on which port?

Write the list **before** opening the console:

```
Glue      → RDS         5432
Glue      → Glue        all TCP (self-referencing)
Lambda    → RDS         5432
EMR       → MSK         9098
Client    → OpenSearch  443
```

Each line becomes one security group rule, group-to-group. **If you can't write this list, you don't yet understand the architecture.**

### 4. How many Availability Zones?

Two minimum, three for production. Subnets cost nothing — you only pay for what runs in them.

Know the exceptions:
- An **EMR cluster lives in one AZ** deliberately (shuffle performance)
- **MSK** wants broker count to be a multiple of AZ count, with replication factor = AZ count
- **RDS Multi-AZ** is for availability, not read scaling — a standby you cannot query

### 5. What does the networking itself cost?

| Component | Cost |
|---|---|
| VPC, subnets, route tables, IGW, security groups, NACLs | **Free** |
| Gateway endpoints (S3, DynamoDB) | **Free** |
| **NAT Gateway** | **~$33/month each + $0.045/GB** |
| Interface endpoint | ~$7/month each + data |
| Cross-AZ data transfer | ~$0.01/GB each direction |
| Elastic IP, unattached | ~$3.60/month |

---

### Design review checklist

Run this against any VPC, including your own:

- [ ] Is anything in a public subnet that doesn't need to be?
- [ ] Does every private route table have an S3 gateway endpoint?
- [ ] Are there NAT Gateways, and is each one genuinely necessary?
- [ ] Does every security group rule reference a **group**, not a CIDR?
- [ ] Is any security group open to `0.0.0.0/0` on anything other than 443?
- [ ] Do distributed services (Glue, EMR, MSK, OpenSearch) have self-referencing rules?
- [ ] Is every subnet **explicitly associated** with the route table you think it is?
- [ ] Are DNS hostnames and DNS resolution enabled? (RDS and MSK endpoints won't resolve otherwise)
- [ ] Are there at least two AZs for anything that must stay up?
- [ ] Are unattached Elastic IPs lying around?

---

<a name="part-4"></a>
## Part 4 — Exam quick reference (DEA-C01)

| The question says… | The answer is… |
|---|---|
| "Data must never traverse the public internet" | **VPC endpoints** — gateway for S3/DynamoDB, interface for the rest |
| "Glue job in a VPC times out / can't reach S3" | Missing **S3 gateway endpoint** (or missing self-referencing SG rule) |
| "Reduce NAT Gateway costs" | Replace with **gateway endpoints** where the traffic is S3/DynamoDB |
| "Allow the application tier to reach the database" | Security group rule, **source = the app's security group** |
| "Block a specific malicious IP range" | **NACL** with a Deny rule — security groups can't deny |
| "Why can't my private instance reach the internet?" | No `0.0.0.0/0` route, or no NAT Gateway |
| "Make a subnet public" | Add `0.0.0.0/0 → IGW` to its **route table** |
| "Return traffic is being blocked" | A **NACL** — they're stateless and need explicit return rules |
| "RDS endpoint won't resolve" | **DNS hostnames / DNS resolution** not enabled on the VPC |
| "Survive the loss of a data centre" | Resources across **two or more AZs** |
| "Connect two VPCs" | **Peering** (few, non-transitive) or **Transit Gateway** (many, hub-and-spoke) |
| "Expose one service privately to another account" | **PrivateLink** — not peering |

---

## The one-paragraph version

> A **VPC** is your private network. **Subnets** slice it and pin each slice to one data centre. **Route tables** decide where traffic may go — and a subnet is public only because its route table has a line pointing at the internet gateway. **Endpoints** give private subnets a free, private path to AWS services so you can avoid a NAT Gateway. **Security groups** then decide what may talk to what, and you reference security groups rather than IP addresses so the rules survive the infrastructure changing underneath them.

---

*Part of the [CityMove Analytics AWS Data Engineering Lab](../README.md). Written during Project 0.*
