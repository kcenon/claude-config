---
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

# REST API Design Standards

## URL Structure

- Use nouns for resources: `/users`, `/orders`
- Use plural forms: `/users` not `/user`
- Nest for relationships: `/users/{id}/orders`
- Use hyphens for multi-word: `/order-items`
- Keep URLs lowercase

## HTTP Methods

- GET: Retrieve resource(s) - idempotent
- POST: Create new resource
- PUT: Full update of resource - idempotent
- PATCH: Partial update of resource
- DELETE: Remove resource - idempotent

## Response Codes

- 200: Success with body
- 201: Created (with Location header)
- 204: Success without body
- 400: Bad request (client error)
- 401: Unauthorized
- 403: Forbidden
- 404: Not found
- 409: Conflict
- 422: Unprocessable entity
- 500: Internal server error

## Request/Response Format

- Use JSON for request/response bodies
- Include Content-Type header
- Wrap collections in object: `{ "data": [], "meta": {} }`
- Use camelCase for JSON properties
- Include pagination for lists

## Versioning

- Use URL versioning: `/api/v1/users`
- Or header versioning: `Accept: application/vnd.api+json;version=1`
- Never break backwards compatibility within version
- Deprecate before removing

## Error Responses

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human readable message",
    "details": []
  }
}
```
