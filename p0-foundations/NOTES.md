# P0 — working notes

The rule: the moment something fails, paste the **verbatim** error here with a timestamp.
Once you've fixed it, add the actual cause underneath. Don't tidy it up — the mess is the
value. Every "what broke" section and every LinkedIn gotcha comes out of this file.

---

## Template

### <date> — <short description>

**What I ran**
```
```

**Error, verbatim**
```
```

**What I thought was wrong**

**What was actually wrong**

**How I'd spot it faster next time**

---
### 11 Oct — Bedrock playground, brand new account
Error: ThrottlingException — "Too many tokens per day, please wait before trying again"
Thought: I had burned through my credits already.
Actually: new accounts get a per-model daily token quota that is near zero
before you have made a single request.
Fix: switch model, or wait for the daily reset. Check Bedrock > Quotas.

### 11 Oct — AWS Builder ID MFA, registering a second device
Error: Windows Security — "There was a problem saving your passkey"
Thought: Windows Hello was broken. It signs me into the laptop fine.
Actually: Windows 10. Signing in with Hello is not the same as *creating* a
passkey — that needs a TPM-backed discoverable credential, which Win 10's
platform authenticator handles badly.
Fix: used a second authenticator app with cloud backup instead.

### 11–19 Oct — Region locked, no Identity Center, no DMS
Error: "Region Europe (Ireland) unavailable". IAM Identity Center greyed out.
DMS and Managed Flink missing entirely.
Thought: my account was broken or misconfigured.
Actually: the new project-based AWS sign-up places your account inside an
AWS-managed Organization with SCPs you cannot edit. RegionFloor pins
aws:RequestedRegion to one region. The Paid Plan SCP is an allow list that
omits DMS and Flink. BlockOrgEscape denies sso:CreateInstance outright.
Fix: created a classic account via "Sign up for AWS (advanced)" and kept the
original as a sandbox with its $200 of credits.
Lesson: "service not supported" was never technical — it was policy.

### 2 Nov — Identity Center greyed out again
Error: IAM Identity Center showed "Available with advanced features".
Thought: something had broken in the new account.
Actually: I was signed into citymove-lab, not citymove-platform. Two accounts,
two browser profiles, and I had not checked the account ID in the top right.
Fix: switched accounts. Cost me ten minutes.
Lesson: check the account ID before doing anything. With two accounts, the
resource you forget will be in the one you were not looking at.