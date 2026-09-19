# API Design

This guideline establishes best practices for designing RESTful and GraphQL APIs.

## RESTful Principles

Follow REST conventions for resource naming, HTTP methods, and status codes.

## Versioning Strategy

Implement clear API versioning to maintain backward compatibility.

## Consistent Responses

Use consistent response formats, error structures, and HTTP status codes across all endpoints.

## Rate Limiting and Pagination

Implement rate limiting and pagination for resource-intensive endpoints.

## Error Handling

Every endpoint returns the `ApiError` shape below. `rest-api.md` cites this block as
the canonical error format, so it stays in the rule.

<details>
<summary>Standardized Error Responses</summary>

```typescript
// Error response format
interface ApiError {
    error: string;           // Error type
    message: string;         // Human-readable message
    code?: string;           // Application-specific error code
    details?: any;           // Additional error details
    timestamp: string;       // ISO 8601 timestamp
    path: string;            // Request path
    requestId?: string;      // Trace ID
}

// Error handler middleware
app.use((err: any, req: Request, res: Response, next: NextFunction) => {
    const errorResponse: ApiError = {
        error: err.name || 'InternalServerError',
        message: err.message || 'An unexpected error occurred',
        code: err.code,
        details: err.details,
        timestamp: new Date().toISOString(),
        path: req.path,
        requestId: req.headers['x-request-id'] as string
    };

    // Log error
    console.error({
        ...errorResponse,
        stack: err.stack
    });

    // Determine status code
    const statusCode = err.statusCode || 500;

    // Don't leak internal errors in production
    if (statusCode === 500 && process.env.NODE_ENV === 'production') {
        delete errorResponse.details;
        errorResponse.message = 'Internal server error';
    }

    res.status(statusCode).json(errorResponse);
});

// Custom error classes
class ValidationError extends Error {
    statusCode = 400;
    code = 'VALIDATION_ERROR';
    details: any;

    constructor(message: string, details?: any) {
        super(message);
        this.name = 'ValidationError';
        this.details = details;
    }
}

class NotFoundError extends Error {
    statusCode = 404;
    code = 'NOT_FOUND';

    constructor(resource: string) {
        super(`${resource} not found`);
        this.name = 'NotFoundError';
    }
}

// Usage
app.get('/api/v1/users/:id', async (req, res, next) => {
    try {
        const user = await User.findById(req.params.id);
        if (!user) {
            throw new NotFoundError('User');
        }
        res.json(user);
    } catch (error) {
        next(error);
    }
});
```
</details>

> Examples: see `.claude/reference/api/api-design-examples.md`
