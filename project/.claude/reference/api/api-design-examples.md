---
alwaysApply: false
---

# API Design Examples

Worked REST, GraphQL, versioning, rate-limiting and pagination samples. Companion to `.claude/rules/api/api-design.md`, which keeps the principles.

> **Loading**: Lives in `.claude/reference/`, outside the auto-loaded `.claude/rules/` tree, so it is never injected automatically. Load with `@load: reference/api-design-examples`.

## RESTful API Design

### Resource Naming and HTTP Methods

```typescript
// GOOD: RESTful resource naming
GET    /api/v1/users              // List all users
GET    /api/v1/users/123          // Get specific user
POST   /api/v1/users              // Create new user
PUT    /api/v1/users/123          // Update entire user
PATCH  /api/v1/users/123          // Partial update
DELETE /api/v1/users/123          // Delete user

// Nested resources
GET    /api/v1/users/123/posts    // Get posts for user 123
POST   /api/v1/users/123/posts    // Create post for user 123
GET    /api/v1/posts/456/comments // Get comments for post 456

// BAD: Non-RESTful naming
GET    /api/v1/getAllUsers        // Don't use verbs in URLs
POST   /api/v1/user/create        // Don't use actions
GET    /api/v1/users/123/delete   // Use DELETE method instead
```

```python
# Flask RESTful API example
from flask import Flask, jsonify, request
from http import HTTPStatus

app = Flask(__name__)

@app.route('/api/v1/users', methods=['GET'])
def list_users():
    page = request.args.get('page', 1, type=int)
    limit = request.args.get('limit', 20, type=int)

    users = User.query.paginate(page=page, per_page=limit)

    return jsonify({
        'data': [user.to_dict() for user in users.items],
        'pagination': {
            'page': users.page,
            'limit': limit,
            'total': users.total,
            'pages': users.pages
        }
    }), HTTPStatus.OK

@app.route('/api/v1/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    user = User.query.get_or_404(user_id)
    return jsonify(user.to_dict()), HTTPStatus.OK

@app.route('/api/v1/users', methods=['POST'])
def create_user():
    data = request.get_json()

    # Validation
    if not data or not data.get('email'):
        return jsonify({
            'error': 'Validation failed',
            'message': 'Email is required'
        }), HTTPStatus.BAD_REQUEST

    user = User(**data)
    db.session.add(user)
    db.session.commit()

    return jsonify(user.to_dict()), HTTPStatus.CREATED

@app.route('/api/v1/users/<int:user_id>', methods=['PATCH'])
def update_user(user_id):
    user = User.query.get_or_404(user_id)
    data = request.get_json()

    # Only update provided fields
    for key, value in data.items():
        if hasattr(user, key):
            setattr(user, key, value)

    db.session.commit()
    return jsonify(user.to_dict()), HTTPStatus.OK
```

### HTTP Status Codes

```typescript
// Status code usage guide

// Success 2xx
200 OK                   // GET, PUT, PATCH success
201 Created              // POST success
204 No Content           // DELETE success

// Client Error 4xx
400 Bad Request          // Invalid syntax or validation error
401 Unauthorized         // Authentication required
403 Forbidden            // Authenticated but not authorized
404 Not Found            // Resource doesn't exist
409 Conflict             // Resource conflict (e.g., duplicate)
422 Unprocessable Entity // Semantic validation error
429 Too Many Requests    // Rate limit exceeded

// Server Error 5xx
500 Internal Server Error // Unexpected server error
503 Service Unavailable   // Server temporarily unavailable

// Example implementation
app.post('/api/v1/users', async (req, res) => {
    try {
        // Validation
        const errors = validateUser(req.body);
        if (errors.length > 0) {
            return res.status(400).json({
                error: 'Validation failed',
                details: errors
            });
        }

        // Check for existing user
        const existing = await User.findByEmail(req.body.email);
        if (existing) {
            return res.status(409).json({
                error: 'Conflict',
                message: 'User with this email already exists'
            });
        }

        // Create user
        const user = await User.create(req.body);

        return res.status(201).json({
            data: user,
            message: 'User created successfully'
        });

    } catch (error) {
        console.error(error);
        return res.status(500).json({
            error: 'Internal server error',
            message: 'An unexpected error occurred'
        });
    }
});
```

### API Versioning

```typescript
// Method 1: URL Path versioning (recommended)
app.use('/api/v1', routesV1);
app.use('/api/v2', routesV2);

// Example: Breaking change in v2
// V1: Returns user.name as single string
app.get('/api/v1/users/:id', (req, res) => {
    const user = {
        id: 1,
        name: "John Doe",
        email: "john@example.com"
    };
    res.json(user);
});

// V2: Returns user.name as object
app.get('/api/v2/users/:id', (req, res) => {
    const user = {
        id: 1,
        name: {
            first: "John",
            last: "Doe"
        },
        email: "john@example.com"
    };
    res.json(user);
});

// Method 2: Header versioning
app.use((req, res, next) => {
    const version = req.headers['api-version'] || '1';
    req.apiVersion = version;
    next();
});

// Method 3: Accept header versioning
// Accept: application/vnd.myapi.v2+json
```

## GraphQL API Design

### Schema Design

```graphql
# schema.graphql

type User {
    id: ID!
    email: String!
    name: String!
    posts: [Post!]!
    createdAt: DateTime!
}

type Post {
    id: ID!
    title: String!
    content: String!
    author: User!
    comments: [Comment!]!
    published: Boolean!
    createdAt: DateTime!
    updatedAt: DateTime!
}

type Comment {
    id: ID!
    text: String!
    author: User!
    post: Post!
    createdAt: DateTime!
}

# Pagination types
type PageInfo {
    hasNextPage: Boolean!
    hasPreviousPage: Boolean!
    startCursor: String
    endCursor: String
}

type UserConnection {
    edges: [UserEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
}

type UserEdge {
    node: User!
    cursor: String!
}

# Input types for mutations
input CreateUserInput {
    email: String!
    name: String!
    password: String!
}

input UpdateUserInput {
    name: String
    email: String
}

# Query root
type Query {
    user(id: ID!): User
    users(first: Int, after: String): UserConnection!
    posts(authorId: ID, published: Boolean): [Post!]!
    post(id: ID!): Post
}

# Mutation root
type Mutation {
    createUser(input: CreateUserInput!): User!
    updateUser(id: ID!, input: UpdateUserInput!): User!
    deleteUser(id: ID!): Boolean!

    createPost(title: String!, content: String!): Post!
    publishPost(id: ID!): Post!
}

# Subscription root
type Subscription {
    postAdded: Post!
    commentAdded(postId: ID!): Comment!
}

# Custom scalars
scalar DateTime
```

```typescript
// GraphQL resolvers
import { GraphQLError } from 'graphql';

const resolvers = {
    Query: {
        user: async (_, { id }, context) => {
            if (!context.user) {
                throw new GraphQLError('Unauthorized', {
                    extensions: { code: 'UNAUTHENTICATED' }
                });
            }

            const user = await User.findById(id);
            if (!user) {
                throw new GraphQLError('User not found', {
                    extensions: { code: 'NOT_FOUND' }
                });
            }

            return user;
        },

        users: async (_, { first = 20, after }, context) => {
            const users = await User.paginate({ first, after });

            return {
                edges: users.map(user => ({
                    node: user,
                    cursor: user.id
                })),
                pageInfo: {
                    hasNextPage: users.length === first,
                    hasPreviousPage: !!after,
                    startCursor: users[0]?.id,
                    endCursor: users[users.length - 1]?.id
                },
                totalCount: await User.count()
            };
        }
    },

    Mutation: {
        createUser: async (_, { input }, context) => {
            // Validate input
            if (!isValidEmail(input.email)) {
                throw new GraphQLError('Invalid email format', {
                    extensions: { code: 'BAD_USER_INPUT' }
                });
            }

            // Check for existing user
            const existing = await User.findByEmail(input.email);
            if (existing) {
                throw new GraphQLError('Email already in use', {
                    extensions: { code: 'CONFLICT' }
                });
            }

            const user = await User.create(input);
            return user;
        },

        updateUser: async (_, { id, input }, context) => {
            // Authorization check
            if (!context.user || context.user.id !== id) {
                throw new GraphQLError('Forbidden', {
                    extensions: { code: 'FORBIDDEN' }
                });
            }

            const user = await User.findByIdAndUpdate(id, input);
            return user;
        }
    },

    User: {
        posts: async (parent) => {
            return await Post.findByAuthorId(parent.id);
        }
    },

    Post: {
        author: async (parent) => {
            return await User.findById(parent.authorId);
        },
        comments: async (parent) => {
            return await Comment.findByPostId(parent.id);
        }
    }
};
```

## Rate Limiting

### Rate Limiting Implementation

```typescript
// Express rate limiting middleware
import rateLimit from 'express-rate-limit';
import RedisStore from 'rate-limit-redis';
import Redis from 'ioredis';

const redis = new Redis({
    host: process.env.REDIS_HOST,
    port: process.env.REDIS_PORT
});

// Global rate limit
const globalLimiter = rateLimit({
    store: new RedisStore({
        client: redis,
        prefix: 'rl:global:'
    }),
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // 100 requests per window
    message: {
        error: 'Too many requests',
        retryAfter: 900 // seconds
    },
    standardHeaders: true, // Return rate limit info in headers
    legacyHeaders: false
});

// Stricter limit for auth endpoints
const authLimiter = rateLimit({
    store: new RedisStore({
        client: redis,
        prefix: 'rl:auth:'
    }),
    windowMs: 15 * 60 * 1000,
    max: 5, // Only 5 attempts per 15 min
    skipSuccessfulRequests: true // Don't count successful logins
});

// Per-user rate limiting
const createUserLimiter = (userId: string) => {
    return rateLimit({
        store: new RedisStore({
            client: redis,
            prefix: `rl:user:${userId}:`
        }),
        windowMs: 60 * 1000, // 1 minute
        max: 60 // 60 requests per minute per user
    });
};

// Apply rate limiters
app.use('/api/', globalLimiter);
app.use('/api/v1/auth/', authLimiter);

// Per-endpoint custom limits
app.post('/api/v1/expensive-operation',
    rateLimit({ windowMs: 60000, max: 5 }),
    expensiveOperationHandler
);
```

```python
# Flask rate limiting with Flask-Limiter
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    storage_uri="redis://localhost:6379",
    default_limits=["200 per day", "50 per hour"]
)

@app.route("/api/v1/users")
@limiter.limit("10 per minute")
def list_users():
    return jsonify(users)

@app.route("/api/v1/auth/login", methods=["POST"])
@limiter.limit("5 per 15 minutes")
def login():
    return jsonify({"token": "..."})

# Exempt specific routes
@app.route("/api/v1/health")
@limiter.exempt
def health_check():
    return jsonify({"status": "ok"})
```
