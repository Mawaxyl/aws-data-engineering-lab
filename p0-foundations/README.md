# P0 — Foundations: identity, access and networking

> Part of the **CityMove Analytics** AWS data engineering lab.
> Services: IAM, VPC, KMS, CLI, Identity Center

---

## 1. Business problem

_What CityMove needs and why the current situation doesn't deliver it. Two or three
sentences, no AWS service names._

## 2. Architecture

![architecture](../docs/diagrams/p0-architecture.png)

_Draw it in draw.io or Excalidraw with the official AWS icon set. Show VPC and subnet
boundaries, label arrows with the mechanism ("DMS CDC", "Firehose, 60s buffer"), and
draw the failure paths, not just the happy path._

| Service | Why this one, and not the alternative |
| --- | --- |
|  |  |

## 3. The data

| Source | URL | Size | What it is |
| --- | --- | --- | --- |
|  |  |  |  |

## 4. Build in the console

_Numbered steps. Note what each option is actually called — that's what the exam tests._

## 5. Rebuild with CLI / IaC

_Scripts live in `infra/`. Delete the console version first and rebuild from code._

## 6. Test and monitor

**Data quality**

**CloudWatch metrics and alarms**

**Results — the numbers that make the post worth reading**

| Measure | Before | After |
| --- | --- | --- |
| Query runtime |  |  |
| Data scanned |  |  |

## 7. Security review

_The five questions, answered for every service in this project._

| Service | Who can access it (IAM) | At rest | In transit | Network | Audit |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

## Cost

| Item | Rate | Hours used | Cost |
| --- | --- | --- | --- |
|  |  |  |  |

**Actual cost from Cost Explorer (filter: `project=p0`):** $

## Teardown

- [ ]
- [ ] Verified in Cost Explorer the next day that daily cost returned to baseline

## Lessons learned

_See `NOTES.md` for the raw errors. This section is the distilled version — it becomes
the "what broke" part of the blog post._

## Links

- Blog post:
- LinkedIn post:
- Diagram source: `../docs/diagrams/p0-architecture.drawio`
