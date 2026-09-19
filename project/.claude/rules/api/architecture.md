---
alwaysApply: false
paths:
  - "**/api/**"
  - "**/routes/**"
  - "**/endpoints/**"
  - "**/controllers/**"
  - "**/handlers/**"
  - "**/*.controller.ts"
  - "**/*.handler.ts"
  - "**/openapi.*"
  - "**/swagger.*"
---

# Architecture and Design Principles

This guideline establishes architectural patterns and SOLID design principles.

## SOLID Principles

> **Scope**: SOLID principles in API/service architecture context.
> For core SRP and modularity guidelines, see [`coding/standards.md`](../coding/standards.md#single-responsibility).

Follow SOLID principles for object-oriented design: Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion.

## Layered Architecture

Separate concerns into distinct layers (presentation, business logic, data access).

## Design Patterns

Apply appropriate design patterns (Factory, Strategy, Observer, etc.) to solve common problems.

## Microservices Considerations

When applicable, design services to be loosely coupled, independently deployable, and organized around business capabilities.

> Examples: see `.claude/reference/api/architecture-examples.md`
