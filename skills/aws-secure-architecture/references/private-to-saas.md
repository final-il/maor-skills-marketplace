# Private Account → SaaS via API Gateway Proxy

This pattern enables an air-gapped AWS account (no internet access) to call external SaaS APIs through a controlled proxy in a second AWS account.

## Architecture

```
┌─────────────────────────┐     ┌─────────────────────────────┐
│  Private Account        │     │  Egress Proxy Account       │
│  (No Internet)          │     │                             │
│                         │     │  ┌───────────────────────┐  │
│  ┌─────────────┐        │     │  │ API Gateway (Private) │  │
│  │  Workload   │──VPC───┼─────┼──│  + Resource Policy    │  │
│  │  (Lambda/   │ Endpt  │     │  │  + WAF                │  │
│  │   ECS/EC2)  │        │     │  └──────────┬────────────┘  │
│  └─────────────┘        │     │             │               │
│                         │     │  ┌──────────▼────────────┐  │
│  No IGW, No NAT        │     │  │ Lambda / HTTP Proxy    │  │
│  No default route       │     │  │  + Outbound control    │  │
│                         │     │  └──────────┬────────────┘  │
└─────────────────────────┘     │             │               │
                                │  ┌──────────▼────────────┐  │
                                │  │ AWS Network Firewall   │  │
                                │  │  + Domain allowlist    │  │
                                │  └──────────┬────────────┘  │
                                │             │               │
                                │  ┌──────────▼────────────┐  │
                                │  │ NAT Gateway → IGW      │  │
                                │  │  (egress only)         │  │
                                │  └───────────────────────┘  │
                                └─────────────────────────────┘
                                              │
                                     ┌────────▼────────┐
                                     │  External SaaS  │
                                     │  (api.vendor.com)│
                                     └─────────────────┘
```

## Data Flow (Step by Step)

1. **Workload** in private account initiates HTTPS request to the VPC Interface Endpoint for API Gateway
2. **VPC Endpoint** routes traffic privately (over AWS backbone, not internet) to API Gateway in the egress proxy account
3. **VPC Endpoint Policy** (Gate 1) restricts which API Gateway APIs can be invoked through this endpoint
4. **API Gateway Resource Policy** (Gate 2) validates the source VPC endpoint, source account, and rejects all other callers
5. **WAF** (Gate 3) inspects the request for injection attacks, rate limiting, and request size
6. **API Gateway** routes to a Lambda integration (or HTTP proxy integration)
7. **Lambda / Proxy** (Gate 4) can add authentication headers (API keys, OAuth tokens from Secrets Manager), transform requests, and enforce business logic (e.g., only allow GET to specific paths)
8. **Security Group on Lambda ENI** (Gate 5) restricts outbound to specific CIDR/port
9. **Network Firewall** (Gate 6) inspects outbound traffic and enforces domain allowlist — only `api.vendor.com` is permitted
10. **NAT Gateway** provides internet egress (outbound only — no inbound path exists)
11. **Response** travels back the same path

## Security Control Chain

```
Connection: Private Workload → External SaaS API
Purpose: Allow specific API calls to approved SaaS vendors

Security Control Chain:
  Gate 1: VPC Endpoint Policy — Limits which API GW resources can be called
  Gate 2: API GW Resource Policy — Only accepts calls from specific VPC endpoint + account
  Gate 3: WAF — Rate limiting, payload inspection, IP reputation
  Gate 4: Lambda Proxy — Business logic, auth injection, path/method filtering
  Gate 5: Security Group — Outbound port/protocol restriction
  Gate 6: Network Firewall — Domain-based allowlist (TLS SNI inspection)
  Gate 7: SCP on Private Account — Deny igw, nat-gw, public IP creation
  Gate 8: SCP on Proxy Account — Deny modification of Network Firewall rules by non-admin

What happens if a single gate fails:
  - Endpoint policy bypassed → API GW resource policy still blocks unauthorized callers
  - API GW resource policy bypassed → Lambda still controls which external endpoints are called
  - Lambda compromised → Network Firewall still blocks non-allowlisted domains
  - Network Firewall bypassed → SCP still prevents the private account from creating its own internet path
```

## Key Configuration Details

### VPC Endpoint Policy (Private Account)
```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "arn:aws:execute-api:REGION:PROXY_ACCOUNT_ID:API_ID/*",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalAccount": "PRIVATE_ACCOUNT_ID"
        }
      }
    }
  ]
}
```

### API Gateway Resource Policy (Proxy Account)
```json
{
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "arn:aws:execute-api:REGION:PROXY_ACCOUNT_ID:API_ID/*",
      "Condition": {
        "StringNotEquals": {
          "aws:sourceVpce": "vpce-XXXXXXXXX"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "arn:aws:execute-api:REGION:PROXY_ACCOUNT_ID:API_ID/*",
      "Condition": {
        "StringEquals": {
          "aws:sourceVpce": "vpce-XXXXXXXXX"
        }
      }
    }
  ]
}
```

### SCP — Deny Internet Access in Private Account
```json
{
  "Statement": [
    {
      "Sid": "DenyInternetAccess",
      "Effect": "Deny",
      "Action": [
        "ec2:CreateInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:CreateNatGateway",
        "ec2:AllocateAddress",
        "ec2:AssociateAddress"
      ],
      "Resource": "*"
    }
  ]
}
```

### Network Firewall Domain Allowlist
```
.strict-order
pass tls any any -> $EXTERNAL_NET 443 (tls.sni; content:"api.vendor.com"; nocase; endswith; msg:"Allow vendor API"; sid:1; rev:1;)
drop tls any any -> $EXTERNAL_NET any (msg:"Block all other TLS"; sid:2; rev:1;)
drop tcp any any -> $EXTERNAL_NET any (msg:"Block all other TCP"; sid:3; rev:1;)
```

## Risks Specific to This Pattern

| Risk | Likelihood | Impact | Mitigation | Residual |
|------|-----------|--------|------------|----------|
| DNS exfiltration from private account | Medium | High | Use Route 53 Resolver with DNS Firewall to block non-allowlisted domains. Log all DNS queries. | Encoded data in allowed domain queries (subdomain encoding) — mitigate with DNS query logging + anomaly detection |
| Lambda proxy compromise (SSRF) | Low | High | Restrict Lambda outbound SG, use Network Firewall allowlist, run Lambda in dedicated subnet | If attacker gains code execution in Lambda, they can only reach allowlisted domains |
| VPC Endpoint policy misconfiguration | Medium | Medium | Use SCPs to deny `ec2:ModifyVpcEndpoint` except for admin role. Use AWS Config rule to detect drift | Window of exposure between misconfiguration and detection |
| API key/secret leakage from Secrets Manager | Low | High | Use KMS key policy restricting decrypt to Lambda execution role only. Rotate keys automatically | If Lambda role is compromised, secrets are accessible |
| TLS inspection bypass (IP-based connection) | Low | Medium | Network Firewall drops all non-TLS traffic. No bare TCP/IP connections allowed outbound | An attacker who controls a SaaS IP could receive non-TLS traffic if firewall rules have gaps |
| Logging blind spot | Medium | Medium | Enable VPC Flow Logs, CloudTrail, API GW access logs, Network Firewall logs, Lambda logs — all to central account | Log volume may delay detection; ensure alerting on anomalies |
| Cross-account role assumption abuse | Low | High | Use external ID, restrict trust policy to specific roles, require source VPC condition | If an attacker obtains valid credentials with the external ID, they can assume the role |

## DNS Security (Often Overlooked)

DNS is the most commonly forgotten exfiltration channel in air-gapped designs. The private account still needs DNS resolution, and DNS queries leave the VPC by default.

**Controls:**
1. **Route 53 Resolver DNS Firewall** — Create an allowlist of domains the private account can resolve. Block everything else.
2. **DNS query logging** — Log all queries to CloudWatch / S3 for anomaly detection.
3. **Block public DNS** — Ensure the VPC does not have a route to any external DNS resolver (no 0.0.0.0/0 route). Use the VPC-provided DNS (AmazonProvidedDNS) with Resolver rules.
4. **Private Hosted Zones** — For the API Gateway endpoint, use a private hosted zone so the workload resolves to the VPC endpoint IP, not a public IP.
