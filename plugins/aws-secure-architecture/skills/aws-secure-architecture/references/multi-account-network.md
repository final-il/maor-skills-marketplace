# Multi-Account Network Security

Centralized egress, inspection, and shared services across multiple AWS accounts.

## Architecture Overview

```
┌──────────────────────────────────────────────────┐
│              AWS Organizations                    │
│  ┌─────────┐  ┌─────────┐  ┌─────────────────┐  │
│  │Workload │  │Workload │  │ Shared Services  │  │
│  │Acct A   │  │Acct B   │  │ Account          │  │
│  │(Private)│  │(Private)│  │ (DNS, Logging,   │  │
│  └────┬────┘  └────┬────┘  │  KMS, Config)    │  │
│       │             │       └────────┬─────────┘  │
│  ┌────▼─────────────▼───────────────▼──────────┐  │
│  │           Transit Gateway                    │  │
│  └──────────────────┬──────────────────────────┘  │
│                     │                             │
│  ┌──────────────────▼──────────────────────────┐  │
│  │         Network / Egress Account             │  │
│  │  ┌──────────────────────────────────────┐   │  │
│  │  │  Inspection VPC                       │   │  │
│  │  │  - AWS Network Firewall               │   │  │
│  │  │  - NAT Gateway (egress only)          │   │  │
│  │  │  - No inbound from internet           │   │  │
│  │  └──────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

## Account Structure

| Account | Purpose | Internet Access |
|---------|---------|----------------|
| Management | Organizations, SCPs, billing | Limited (admin only) |
| Security / Log Archive | CloudTrail, Config, GuardDuty, Flow Logs | No |
| Shared Services | DNS, KMS, internal tooling | VPC endpoints only |
| Network / Egress | Transit Gateway, Network Firewall, NAT GW | Controlled egress only |
| Workload Accounts | Application workloads | None (via SCP) |

## Security Controls by Layer

### Organization Layer (SCPs)
- Deny internet gateway / NAT gateway creation in workload accounts
- Deny disabling of CloudTrail, Config, GuardDuty
- Deny leaving the organization
- Restrict regions to approved list
- Deny public S3 buckets and public RDS instances

### Transit Gateway
- Separate route tables per security zone (workload, shared, egress)
- Workload accounts can only route to shared services and egress — not to each other (unless explicitly needed)
- Blackhole routes for internet-bound traffic from accounts that shouldn't have egress
- TGW Flow Logs for cross-account traffic visibility

### Inspection VPC (Network Account)
- All egress traffic routes through Network Firewall before NAT Gateway
- Domain-based allowlisting (TLS SNI inspection)
- Stateful rule groups per workload account (different accounts may have different allowed destinations)
- Alert-mode rules for suspicious but not blocked traffic
- Centralized logging of all firewall decisions

### DNS
- Route 53 Resolver in shared services account with forwarding rules
- DNS Firewall with domain allowlists per workload account
- DNS query logging to central log archive
- Private hosted zones for internal service discovery

### Monitoring
- VPC Flow Logs from all VPCs → central S3 bucket in log archive account
- CloudTrail organization trail → log archive
- GuardDuty with delegated admin in security account
- AWS Config with organization-wide conformance packs
- Security Hub aggregation in security account

## Risks

| Risk | Mitigation |
|------|-----------|
| Transit Gateway misconfiguration allows cross-account lateral movement | TGW route table isolation, network segmentation tests, Config rules |
| Centralized egress is a single point of failure | Multi-AZ Network Firewall, NAT GW per AZ, health checks |
| Shared services account compromise affects all accounts | Least-privilege access, separate admin roles, break-glass procedures |
| Log archive tampering | S3 Object Lock (compliance mode), separate account, MFA delete |
| SCP change weakens all accounts | SCP changes require approval workflow, CloudTrail alerting on SCP modifications |
