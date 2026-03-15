# Zero-Trust Service Mesh in AWS

Service-to-service authentication and authorization within and across VPCs, without relying on network position as a trust signal.

## When to Use

- Microservices that need mutual authentication
- Cross-VPC or cross-account service communication
- Environments where "inside the VPC" should not imply trust
- Compliance requirements for service-level access control and audit

## Architecture Options

### Option 1: VPC Lattice (AWS-native)

Best for: AWS-native workloads (Lambda, ECS, EC2) that need service-to-service auth without managing infrastructure.

```
Service A ──► VPC Lattice Service Network ──► Service B
              (auth policy per service)
```

**Security controls:**
- IAM auth policies on each service — caller must present valid SigV4 credentials
- Service network policies control which VPCs/accounts can participate
- Per-service access policies (allow specific principals, deny all others)
- Built-in access logging (who called what, when, allowed/denied)
- No need to manage certificates or sidecars

### Option 2: PrivateLink (Point-to-Point)

Best for: Exposing a specific service to specific consumers across accounts, with strong network-level isolation.

```
Consumer VPC ──► VPC Endpoint ──► PrivateLink ──► NLB ──► Service
                 (endpoint policy)                (target group)
```

**Security controls:**
- Endpoint policy restricts which principals can use the endpoint
- NLB security groups (if using ALB-type target) or NACLs
- Service provider controls who can create endpoints to their service (allowlisted accounts/principals)
- Traffic stays on AWS backbone — never traverses internet

### Option 3: Service Mesh (Envoy / App Mesh / Istio)

Best for: Complex routing, mTLS between services, advanced traffic management (canary, circuit breaking).

**Security controls:**
- mTLS between all services (certificate-based identity)
- Authorization policies per service (which service can call which endpoint)
- Certificate management via ACM Private CA or external CA
- Envoy access logs for full request-level audit trail

## Common Security Controls (All Options)

| Control | Purpose |
|---------|---------|
| IAM roles per service | Each service has its own identity — no shared credentials |
| Resource policies | Each service explicitly declares who can call it |
| Encryption in transit | mTLS or TLS 1.2+ for all service-to-service traffic |
| Access logging | Every call logged with caller identity, action, and result |
| Security groups | Even with auth policies, restrict network-level access to known CIDR/SG |
| Secrets rotation | API keys, tokens, and certificates rotated automatically |

## Risks

| Risk | Mitigation |
|------|-----------|
| Overly permissive auth policies ("Allow *") | Automated policy review (IAM Access Analyzer, custom Config rules) |
| Certificate expiry breaks service communication | ACM managed renewal, alerting on expiry < 30 days |
| Sidecar/proxy compromise in mesh | Keep mesh control plane isolated, limit sidecar permissions, monitor for anomalous traffic patterns |
| Service identity spoofing | Use IAM roles (not API keys), enforce SigV4 or mTLS, condition on source VPC/account |
| Lateral movement after service compromise | Per-service authorization (not network-wide trust), blast radius limits via separate security groups per service |
