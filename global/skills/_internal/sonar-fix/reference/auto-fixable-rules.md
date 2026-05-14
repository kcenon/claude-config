# Auto-Fixable SonarQube Rules (whitelist)

| Rule  | Type                | Phase | Codified Fix |
|-------|---------------------|-------|--------------|
| S1481 | Unused local        | P2    | TODO: P2     |
| S1128 | Unused import       | P2    | TODO: P2     |
| S1854 | Dead assignment     | P4    | TODO: P4     |
| S1192 | Literal duplication | P4    | TODO: P4     |
| S125  | Commented-out code  | P4    | TODO: P4     |
| S1116 | Empty statement     | P4    | TODO: P4     |

## Excluded (never auto-fixed)
- `security_hotspot` (type): manual security review required
- `vulnerability` (type): manual security review required
- Complexity rules (cognitive/cyclomatic): architectural decisions
- Naming rules: cascade-heavy renames, risk of breaking external callers
