---
name: api-design
description: "Provides API design guidelines for REST endpoints, GraphQL schemas, versioning strategies, error handling conventions, logging, observability, and microservice architecture patterns. Use when designing APIs, reviewing API architecture, implementing new endpoints, setting up monitoring, or planning service boundaries."
allowed-tools:
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Bash
model: sonnet
argument-hint: "<endpoint-or-file>"
paths: "**/api/**, **/routes/**, **/handlers/**"
---

# API Design Skill

## When to Use

- Designing REST or GraphQL APIs
- Architecture and microservices design
- Setting up logging and observability
- Implementing rate limiting or authentication
- Code review for API endpoints

## Reference Documents (Import Syntax)

### API Design
@./reference/api-design.md

### Architecture
@./reference/architecture.md

### Observability
@./reference/logging.md
@./reference/observability.md

## Core Principles

1. **RESTful conventions**: Use proper HTTP methods and status codes
2. **SOLID principles**: Apply design patterns appropriately
3. **Structured logging**: Include context and correlation IDs
4. **Observability**: Implement metrics, traces, and health checks
