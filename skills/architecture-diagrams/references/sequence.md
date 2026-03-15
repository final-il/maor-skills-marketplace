# Sequence Diagrams

## Mermaid

```mermaid
sequenceDiagram
    participant W as Workload
    participant VE as VPC Endpoint
    participant AG as API Gateway
    participant L as Lambda Proxy
    participant S as SaaS API

    W->>VE: HTTPS Request
    VE->>AG: Route via AWS Backbone
    Note over AG: Resource Policy validates source VPCE
    AG->>L: Invoke
    Note over L: Inject auth headers from Secrets Manager
    L->>S: HTTPS + Auth Token
    S-->>L: Response
    L-->>AG: Transform response
    AG-->>VE: Return
    VE-->>W: Response
```

### Key patterns

**Participants**: Define them upfront with aliases for readability.
```
participant Alias as "Display Name"
```

**Arrow types**:
- `->>` solid with arrowhead (request)
- `-->>` dashed with arrowhead (response)
- `->>+` activate target (shows execution bar)
- `-->>-` deactivate (ends execution bar)

**Notes**: Use to annotate security controls and decisions.
```
Note over A: Validates token
Note over A,B: Encrypted with TLS 1.2
Note right of A: Check rate limit
```

**Loops and conditions**:
```
alt Success
    A->>B: 200 OK
else Failure
    A->>B: 403 Forbidden
end

loop Retry 3 times
    A->>B: Request
end
```

**Activation** (shows which component is processing):
```
A->>+B: Request
B-->>-A: Response
```

## PlantUML

```plantuml
@startuml
participant "Workload" as W
participant "VPC Endpoint" as VE
participant "API Gateway" as AG
participant "Lambda" as L
participant "SaaS API" as S

W -> VE : HTTPS Request
activate VE
VE -> AG : AWS Backbone
activate AG
note right: Resource Policy check
AG -> L : Invoke
activate L
note right: Inject auth headers
L -> S : HTTPS + Token
activate S
S --> L : Response
deactivate S
L --> AG : Transformed response
deactivate L
AG --> VE : Return
deactivate AG
VE --> W : Response
deactivate VE
@enduml
```

### Key patterns

**Colors and styling**:
```
participant "Name" as A #LightBlue
```

**Dividers** (separate phases):
```
== Authentication Phase ==
A -> B : Login
== Data Phase ==
A -> B : Request
```

**Groups**:
```
group Security Validation
    A -> B : Validate
    B -> C : Check
end
```
