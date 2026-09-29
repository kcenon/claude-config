# Observability

> **Scope**: API and microservice observability (Node.js, Python, web services).
> For infrastructure/system-level metrics (C/C++), see [`operations/ops.md`](../operations/ops.md).
> Incorporates logging standards (formerly `logging.md`).

Observability practices using the three pillars: **metrics, logs, and traces**.

## Structured Logging

- Use structured (JSON) logging for easier parsing and analysis
- Use appropriate log levels (DEBUG, INFO, WARN, ERROR, FATAL) based on severity
- Include contextual information (request ID, user ID) to trace requests across services
- **Never log sensitive information** such as passwords, tokens, or personal data

## Metrics Collection

Collect and expose key performance indicators (response time, error rate, throughput).

## Distributed Tracing

Implement tracing to follow requests across microservices.

## Health Checks

Provide health and readiness endpoints for monitoring and orchestration.

## Service Level Objectives (SLO)

Define and monitor SLIs/SLOs/SLAs to ensure service reliability.

> Examples: see `.claude/reference/api/observability-examples.md`
