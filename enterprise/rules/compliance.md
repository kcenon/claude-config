# Compliance Rules

> **Scope note**: This file is the authority for organization-wide controls (SOC 2, GDPR, ISO 27001). For product-safety standards used by regulated-industry projects (medical devices, automotive, functional safety) — IEC 62304, ISO 13485, ISO 14971, ISO 26262, IEC 61508, DO-178C — see `project/.claude/rules/compliance/`. The two layers are complementary: this file applies to every project; the per-standard files load on demand via `paths:` triggers.

Organization-wide compliance rules that apply to all projects.

## Data Protection

### Personal Data (GDPR/Privacy)
- **MUST** obtain consent before collecting personal data
- **MUST** provide data deletion capability
- **MUST** encrypt personal data at rest and in transit
- **MUST** document data processing activities

### Data Classification
- **MUST** classify data according to organization policy
- **MUST** apply appropriate controls per classification
- **MUST NOT** mix data of different classification levels

## Audit Requirements

### Logging
- **MUST** log all data access events
- **MUST** retain logs according to retention policy
- **MUST** protect logs from tampering

### Traceability
- **MUST** maintain audit trail for sensitive operations
- **MUST** link changes to authorized requests
- **MUST** document security decisions

## Regulatory Compliance

### Industry Standards
- **MUST** follow applicable industry standards (SOC2, ISO27001, etc.)
- **MUST** document compliance status
- **MUST** address compliance gaps timely

### Legal Requirements
- **MUST** comply with applicable laws and regulations
- **MUST** consult legal team for uncertain cases
- **MUST** document legal decisions

## Third-Party Risk

### Vendor Assessment
- **MUST** assess third-party security before integration
- **MUST** document third-party data flows
- **MUST** review third-party agreements for compliance

---

*Customize these rules according to your organization's compliance requirements.*
