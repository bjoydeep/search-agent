# ACM Search API v2 - Comprehensive Code Analysis

## Table of Contents
1. [Source File Navigation](#source-file-navigation)
2. [Configuration Options](#configuration-options)
3. [GraphQL Implementation](#graphql-implementation)
4. [RBAC Implementation](#rbac-implementation)
5. [Database Integration](#database-integration)
6. [Performance Parameters](#performance-parameters)
7. [Error Patterns](#error-patterns)
8. [Client Integration](#client-integration)
9. [Deployment & Operations](#deployment--operations)

---

## Source File Navigation

### Repository Structure
```
search-v2-api/
├── graph/                    # GraphQL schema and auto-generated resolvers
│   ├── schema.graphqls       # GraphQL schema definition
│   ├── schema.resolvers.go   # Generated resolver implementations
│   └── gqlgen.yml           # GraphQL code generation config
├── pkg/                      # Core application packages
│   ├── config/              # Environment configuration
│   ├── database/            # PostgreSQL connection and event listeners
│   ├── federated/           # Multi-cluster search capabilities
│   ├── metrics/             # Prometheus monitoring
│   ├── rbac/                # Authentication and authorization
│   ├── resolver/            # GraphQL business logic
│   └── server/              # HTTP server and middleware
├── test/                     # Load testing with Locust
├── sslcert/                 # SSL certificate utilities
├── main.go                  # Application entry point
└── Makefile                 # Development and build automation
```

### Key Files by Function

**GraphQL API:**
- `/graph/schema.graphqls` - Complete API schema definition
- `/pkg/resolver/search.go` - Core search query implementation
- `/pkg/resolver/searchComplete.go` - Autocomplete functionality
- `/pkg/resolver/searchSchema.go` - Schema introspection

**Authentication & Authorization:**
- `/pkg/rbac/userData.go` - User permission loading and caching (23.5 KB)
- `/pkg/rbac/authnMiddleware.go` - Authentication middleware
- `/pkg/rbac/authzMiddleware.go` - Authorization middleware
- `/pkg/rbac/tokenReview.go` - JWT token validation

**Database Layer:**
- `/pkg/database/connection.go` - Connection pooling and health checks
- `/pkg/database/listener.go` - PostgreSQL LISTEN/NOTIFY events
- `/pkg/database/listenerTrigger.sql` - Database trigger definitions

**Server & Configuration:**
- `/pkg/server/server.go` - HTTP endpoints and middleware stack
- `/pkg/config/config.go` - Environment variable mapping
- `/pkg/metrics/metrics.go` - Prometheus metric definitions

---

## Configuration Options

### Environment Variables

#### Database Configuration
```bash
# Required - Deployment will fail without these
DB_NAME=searchdb                    # PostgreSQL database name
DB_USER=postgres                    # Database username
DB_PASS=secretpassword              # Database password (URL-encoded internally)

# Optional - Connection settings
DB_HOST=localhost                   # Default: localhost
DB_PORT=5432                       # Default: 5432
```

#### Connection Pool Tuning
```bash
DB_MIN_CONNS=2                     # Minimum pool size
DB_MAX_CONNS=10                    # Maximum pool size
DB_MAX_CONN_IDLE_TIME=300000       # Idle timeout (ms) - Default: 5 minutes
DB_MAX_CONN_LIFETIME=300000        # Connection lifetime (ms) - Default: 5 minutes
```

#### Authentication & Caching
```bash
# Cache TTL Settings
AUTH_CACHE_TTL=60                  # Authentication cache (seconds)
SHARED_CACHE_TTL=300               # Shared resource cache (seconds)
USER_CACHE_TTL=300                 # User-specific cache (seconds)
FEDERATION_CONFIG_TTL=120          # Federation config cache (seconds)

# RBAC Cache Management
RBAC_CACHE_VALIDATION_ENABLED=true    # Enable background cache validation
```

#### Performance Tuning
```bash
# Query Limits
DEFAULT_QUERY_LIMIT=1000           # Default result limit
SLOW_QUERY_LOGGING_THRESHOLD=500   # Log queries > 500ms

# Timeouts
REQUEST_TIMEOUT=120000             # HTTP request timeout (ms) - 2 minutes
FEDERATED_REQUEST_TIMEOUT=60000    # Federated query timeout (ms) - 1 minute

# Server Configuration
SERVER_PORT=4010                   # HTTPS port
PLAYGROUND_MODE=false              # GraphQL playground availability
```

#### Feature Toggles
```bash
FEATURE_FEDERATED_SEARCH=true     # Enable multi-cluster search
FEATURE_FINE_GRAINED_RBAC=true    # Use UserPermissions CRD
FEATURE_SUBSCRIPTION=true          # Enable WebSocket subscriptions
```

#### SSL/TLS Configuration
- Certificates must be available at `./sslcert/tls.crt` and `./sslcert/tls.key`
- Enforces TLS 1.2 minimum with AES-256-GCM cipher suite only
- HTTP/2 is explicitly disabled

---

## GraphQL Implementation

### Schema Overview

The API provides a single Query root with three main operations:

```graphql
type Query {
  search(input: [SearchInput]): [SearchResult]
  searchComplete(property: String!, query: SearchInput, limit: Int): [String]
  searchSchema(input: SearchInput): [String]
  messages: [String]
}

type Subscription {
  searchEvents: Event
}
```

### Core Data Types

#### SearchInput
```graphql
input SearchInput {
  keywords: [String]           # Text search (AND operation)
  filters: [SearchFilter]      # Property-value pairs
  limit: Int                   # Default: 10,000
  offset: Int                  # Pagination offset
  orderBy: String             # Sort by property (ASC/DESC)
  relatedKinds: [String]      # Include related resources
}

input SearchFilter {
  property: String!
  values: [String]!
  operation: String           # =, !=, >, >=, <, <=
}
```

#### SearchResult
```graphql
type SearchResult {
  count: Int                  # Total matching resources
  items: [Map]               # Actual resource data
  related: [SearchRelatedResult] # Related resource counts
}

scalar Map                   # Key-value string pairs
scalar Date                  # RFC3339 format
```

### Query Resolution Patterns

#### Search Query Flow
1. **Input Validation** - Check filters, orderBy format, pagination bounds
2. **RBAC Integration** - Append permission clauses to WHERE conditions
3. **SQL Generation** - Use `goqu` library for dynamic query building
4. **Execution Strategy** - Three queries: count, UIDs, full items
5. **Result Assembly** - Combine counts, items, and related resources

#### Performance Optimizations
- **Distinct Selection**: When ORDER BY is used, include ordering field in SELECT
- **Lazy RBAC Loading**: User permissions loaded only when needed
- **Concurrent Related Queries**: Related resources fetched in parallel
- **Query Type Categorization**: Different SELECT strategies for count vs. items

#### Example Query Usage
```graphql
query SearchPods {
  search(input: [{
    filters: [
      { property: "kind", values: ["Pod"], operation: "=" }
      { property: "namespace", values: ["default"], operation: "=" }
    ]
    keywords: ["nginx"]
    limit: 50
    orderBy: "name ASC"
  }]) {
    count
    items
    related {
      kind
      count
    }
  }
}
```

---

## RBAC Implementation

### Authentication Flow

#### Three-Tier Authorization Model
1. **Cluster Admin Detection** - Check for wildcard "*" permissions
2. **Fine-Grained RBAC** - Query UserPermissions CRD when enabled
3. **Standard RBAC** - Fall back to SelfSubjectAccessReview calls

#### User Data Structure
```go
type UserData struct {
    CsResources      []string           // Cluster-scoped resource access
    NsResources      map[string][]string // Namespace-scoped access
    ManagedClusters  []string           // Accessible managed clusters
    // Cache metadata and validation timestamps
}
```

### Permission Caching Strategy

#### Multi-Component Cache
- **csrCache**: Cluster-scoped resource permissions
- **nsrCache**: Namespace-scoped permissions
- **clustersCache**: Managed cluster access
- **userPermissionCache**: Fine-grained UserPermissions CRD data

#### Cache Validation
- Each component has separate `cacheMetadata` with timestamps
- All components must pass `isValid()` check based on configured TTL
- Background validation via `rbac.ValidateCache()` goroutine
- Cache misses trigger fresh permission loading with user impersonation

#### Concurrent Access Management
- Separate mutex locks for each cache component
- Parallel SSAR API calls using `sync.WaitGroup`
- Copy methods prevent direct mutation of cached data

### Permission Enforcement

#### Query Integration
All database queries automatically include RBAC WHERE clauses:

```sql
-- Example generated SQL with RBAC
SELECT * FROM search.resources
WHERE (kind = 'Pod' AND namespace = 'default')
AND (
  -- Cluster admin check
  cluster IN ('*')
  OR
  -- Namespace-specific access
  (cluster = 'local-cluster' AND namespace IN ('default', 'kube-system'))
  OR
  -- Cluster-scoped resource access
  (namespace IS NULL AND cluster = 'local-cluster')
)
```

#### Access Validation
The `CheckUserHasAccess()` method validates requests against cached permissions:
- Matches verb (get, list, watch)
- Validates API group and resource kind
- Checks cluster and namespace constraints
- Defaults to deny if cache retrieval fails

### Managed Cluster Authorization

#### Discovery Methods
1. **Namespace Scanning** - Users with ManagedClusterView create permissions
2. **Wildcard Elevation** - Broad access grants access to all clusters

#### Permission Loading
```go
// Check if user can create ManagedClusterView in namespace
canCreate := CheckAccess("managedclusterviews", "create", namespace)
if canCreate {
    managedClusters = append(managedClusters, namespace)
}
```

---

## Database Integration

### Connection Management

#### Pool Configuration
```go
config := pgxpool.Config{
    MinConns:        config.DBMinConns,      // Default: 2
    MaxConns:        config.DBMaxConns,      // Default: 10
    MaxConnIdleTime: time.Duration(config.DBMaxConnIdleTime) * time.Millisecond,
    MaxConnLifetime: time.Duration(config.DBMaxConnLifetime) * time.Millisecond,
    MaxConnLifetimeJitter: time.Duration(1) * time.Minute, // Prevent thundering herd
}
```

#### Health Checking
- **afterConnect**: Ping new connections from pool
- **beforeAcquire**: Validate idle connections before reuse
- **Rate Limited**: Skip database ping if checked < 1 second ago
- **Error Handling**: Return nil on failure (no retry logic)

#### SSL Configuration
- Enforces `sslmode=require` in connection string
- No certificate validation configuration visible
- Potential security gap for network-compromised databases

### Query Builder Patterns

#### Dynamic SQL Generation
Uses `goqu` library for type-safe SQL building:

```go
// Example query construction
query := dialect.Select("*").
    From("search.resources").
    Where(goqu.Ex{
        "kind": "Pod",
        "namespace": "default",
    }).
    Limit(uint(limit)).
    Offset(uint(offset))
```

#### Query Type Strategy
Three distinct query patterns:
1. **Count Query**: `SELECT COUNT(DISTINCT uid)` for result totals
2. **UID Query**: `SELECT DISTINCT uid` for relationship queries
3. **Item Query**: `SELECT *` with all filters and pagination

#### RBAC Integration
All queries automatically include permission WHERE clauses:
```go
func (s *SearchResolver) buildSearchQuery(input SearchInput) *goqu.SelectDataset {
    query := s.baseQuery()

    // Apply user filters
    query = s.applyFilters(query, input.Filters)

    // Critical: Always append RBAC constraints
    rbacClause := s.buildRBACClause(s.userData)
    query = query.Where(rbacClause)

    return query
}
```

### Event-Driven Architecture

#### PostgreSQL LISTEN/NOTIFY
- Database triggers notify API of resource changes
- WebSocket subscriptions relay events to connected clients
- Trigger SQL maintained in `/pkg/database/listenerTrigger.sql`

#### Event Processing
```go
type Event struct {
    UID       string    `json:"uid"`
    Operation string    `json:"operation"` // INSERT, UPDATE, DELETE
    NewData   Map       `json:"newData"`
    OldData   Map       `json:"oldData"`
    Timestamp time.Time `json:"timestamp"`
}
```

---

## Performance Parameters

### Query Performance

#### Default Limits
```go
const (
    DefaultQueryLimit = 1000        // Results per query
    MaxQueryLimit     = 10000       // Hard limit
    SlowQueryThreshold = 500        // Log queries > 500ms
)
```

#### Pagination Strategy
- **OFFSET/LIMIT**: Standard SQL pagination
- **Memory Protection**: Hard limits prevent excessive memory usage
- **Related Queries**: Separate limits for relationship data

#### Query Optimization
```go
// Example optimized query with DISTINCT + ORDER BY
if orderBy != "" {
    // Include ORDER BY field in SELECT for DISTINCT compatibility
    selectFields = append(selectFields, orderByField)
}
query = query.Select(selectFields...).Distinct()
```

### Caching Performance

#### TTL Configuration
```bash
# Production Recommended Values
AUTH_CACHE_TTL=300          # 5 minutes - Balance security vs performance
SHARED_CACHE_TTL=600        # 10 minutes - Shared data changes less frequently
USER_CACHE_TTL=300          # 5 minutes - User permissions may change
```

#### Cache Hit Optimization
- **Conditional Loading**: RBAC data loaded only when needed
- **Background Refresh**: `ValidateCache()` prevents expiry-induced latency
- **Component Isolation**: Separate TTLs for different cache layers

#### Memory Management
```go
// Prevent cache growth
func (u *UserData) Copy() *UserData {
    // Create defensive copies to prevent mutations
    return &UserData{
        CsResources:     append([]string{}, u.CsResources...),
        NsResources:     copyMap(u.NsResources),
        ManagedClusters: append([]string{}, u.ManagedClusters...),
    }
}
```

### Connection Pool Tuning

#### Production Settings
```bash
# High-Traffic Environments
DB_MIN_CONNS=5              # Maintain baseline capacity
DB_MAX_CONNS=25             # Allow burst capacity
DB_MAX_CONN_IDLE_TIME=180000 # 3 minutes - Faster cleanup
DB_MAX_CONN_LIFETIME=900000  # 15 minutes - Longer lifetime

# Memory-Constrained Environments
DB_MIN_CONNS=1              # Minimal baseline
DB_MAX_CONNS=5              # Conservative limit
DB_MAX_CONN_IDLE_TIME=60000  # 1 minute - Aggressive cleanup
```

#### Performance Considerations
- **Statement Cache Disabled**: Reduces per-connection memory overhead
- **Connection Jitter**: Prevents synchronized reconnection storms
- **Health Check Throttling**: Minimizes ping overhead

### Federated Search Performance

#### Concurrency Model
```go
// Parallel requests to multiple clusters
var wg sync.WaitGroup
for _, remoteService := range federatedServices {
    wg.Add(1)
    go func(service RemoteSearchService) {
        defer wg.Done()
        response := getFederatedResponse(service, requestBody)
        // Process response
    }(remoteService)
}
wg.Wait() // Bottleneck: Slowest cluster determines total latency
```

#### Optimization Strategies
- **HTTP Client Pooling**: Reuse connections across requests
- **Cluster Filtering**: Only query relevant managed hubs
- **Version Compatibility**: Adapt queries for API version differences

---

## Error Patterns

### Common API Errors

#### Authentication Failures
```json
{
  "errors": [{
    "message": "User has no access to any resources",
    "extensions": {
      "code": "FORBIDDEN"
    }
  }]
}
```

**Code Location**: `/pkg/rbac/userData.go:LoadUserData()`
**Cause**: No cluster-scoped, namespace-scoped, or managed cluster permissions found
**Resolution**: Verify user has appropriate RBAC bindings

#### Database Connection Errors
```json
{
  "errors": [{
    "message": "Database connection failed",
    "extensions": {
      "code": "INTERNAL_ERROR"
    }
  }]
}
```

**Code Location**: `/pkg/database/connection.go:GetConnPool()`
**Cause**: PostgreSQL unavailable or connection pool exhausted
**Resolution**: Check database health and connection pool configuration

#### Query Validation Errors
```json
{
  "errors": [{
    "message": "Invalid filter operation: 'INVALID'",
    "extensions": {
      "code": "BAD_USER_INPUT"
    }
  }]
}
```

**Code Location**: `/pkg/resolver/search.go:validateSearchInput()`
**Cause**: Unsupported filter operation (valid: =, !=, >, >=, <, <=)
**Resolution**: Use supported filter operations

#### Performance Errors
```json
{
  "errors": [{
    "message": "Query timeout exceeded",
    "extensions": {
      "code": "TIMEOUT"
    }
  }]
}
```

**Code Location**: `/pkg/server/server.go` middleware
**Cause**: Query execution > REQUEST_TIMEOUT (default: 2 minutes)
**Resolution**: Optimize query filters or increase timeout

### Error Handling Patterns

#### Graceful Degradation
```go
func (s *SearchResolver) search(ctx context.Context, input []*SearchInput) ([]*SearchResult, error) {
    // Early validation
    if err := s.validateInput(input); err != nil {
        return nil, fmt.Errorf("validation failed: %w", err)
    }

    // Permission check
    if !s.hasRequiredPermissions() {
        return nil, errors.New("insufficient permissions")
    }

    // Execute with timeout
    results, err := s.executeWithTimeout(ctx, input)
    if err != nil {
        s.logError("Search execution failed", err)
        return nil, err
    }

    return results, nil
}
```

#### Structured Error Responses
- **Validation Errors**: Return immediately with descriptive messages
- **Authorization Errors**: Log security events before returning generic message
- **Database Errors**: Log technical details, return user-friendly message
- **Timeout Errors**: Include query complexity suggestions

---

## Client Integration

### HTTP Endpoints

#### Primary GraphQL Endpoint
```
POST https://localhost:4010/searchapi/graphql
Content-Type: application/json
Authorization: Bearer <jwt-token>

{
  "query": "query SearchPods { search(input: [{filters: [...]}]) { count items } }",
  "variables": {},
  "operationName": "SearchPods"
}
```

#### Health Check Endpoints
```bash
# Kubernetes Probes
GET https://localhost:4010/liveness   # Always returns 200 OK
GET https://localhost:4010/readiness  # Returns 200 if database accessible

# Prometheus Metrics
GET https://localhost:4010/metrics    # Metrics in Prometheus format
```

#### Development Tools
```bash
# GraphQL Playground (when PLAYGROUND_MODE=true)
GET https://localhost:4010/playground # Interactive query interface
```

### Authentication Integration

#### JWT Token Requirements
- Token must be valid Kubernetes ServiceAccount token
- Subject extracted from token for RBAC evaluation
- Token forwarded to federated clusters for distributed auth

#### Headers
```bash
Authorization: Bearer <serviceaccount-token>
Content-Type: application/json
```

#### User Impersonation
```bash
# For fine-grained RBAC queries
Impersonate-User: <username>
Impersonate-Groups: <group1,group2>
```

### WebSocket Subscriptions

#### Connection Setup
```javascript
const ws = new WebSocket('wss://localhost:4010/searchapi/graphql', 'graphql-ws');

// Send connection init
ws.send(JSON.stringify({
  type: 'connection_init',
  payload: {
    Authorization: 'Bearer <token>'
  }
}));
```

#### Subscription Query
```graphql
subscription ResourceEvents {
  searchEvents {
    uid
    operation
    newData
    oldData
    timestamp
  }
}
```

#### Event Message Format
```json
{
  "type": "data",
  "id": "1",
  "payload": {
    "data": {
      "searchEvents": {
        "uid": "pod-123",
        "operation": "UPDATE",
        "newData": {"status": "Running"},
        "oldData": {"status": "Pending"},
        "timestamp": "2026-03-24T10:30:00Z"
      }
    }
  }
}
```

### Response Patterns

#### Successful Query Response
```json
{
  "data": {
    "search": [{
      "count": 150,
      "items": [
        {
          "uid": "pod-123",
          "kind": "Pod",
          "name": "nginx-pod",
          "namespace": "default",
          "cluster": "local-cluster"
        }
      ],
      "related": [{
        "kind": "Service",
        "count": 5
      }]
    }]
  }
}
```

#### Error Response Format
```json
{
  "data": null,
  "errors": [{
    "message": "User has no access to any resources",
    "locations": [{"line": 2, "column": 3}],
    "path": ["search"],
    "extensions": {
      "code": "FORBIDDEN"
    }
  }]
}
```

### Client SDK Patterns

#### Query Construction Helper
```javascript
function buildSearchQuery(filters, options = {}) {
  return {
    query: `
      query Search($input: [SearchInput]) {
        search(input: $input) {
          count
          items
          related { kind count }
        }
      }
    `,
    variables: {
      input: [{
        filters: filters,
        limit: options.limit || 1000,
        offset: options.offset || 0,
        orderBy: options.orderBy
      }]
    }
  };
}
```

#### Error Handling Pattern
```javascript
async function executeSearch(query) {
  try {
    const response = await fetch('/searchapi/graphql', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify(query)
    });

    const result = await response.json();

    if (result.errors) {
      throw new Error(result.errors[0].message);
    }

    return result.data;
  } catch (error) {
    console.error('Search failed:', error);
    throw error;
  }
}
```

---

## Deployment & Operations

### Container Configuration

#### Docker Build
```dockerfile
# Multi-stage build for security and efficiency
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest

# Performance: Aggressive garbage collection
ENV GOGC=25

# Security: Non-root execution
USER 1001

# Runtime: Single executable entry point
ENTRYPOINT ["/search-api"]
EXPOSE 4010
```

#### Production Environment Variables
```yaml
env:
  # Required Database Config
  - name: DB_NAME
    value: "searchdb"
  - name: DB_USER
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: username
  - name: DB_PASS
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: password

  # Performance Tuning
  - name: DB_MAX_CONNS
    value: "20"
  - name: REQUEST_TIMEOUT
    value: "180000"  # 3 minutes

  # Feature Configuration
  - name: FEATURE_FEDERATED_SEARCH
    value: "true"
  - name: FEATURE_FINE_GRAINED_RBAC
    value: "true"
```

### Kubernetes Deployment

#### Resource Requirements
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

#### Health Checks
```yaml
livenessProbe:
  httpGet:
    path: /liveness
    port: 4010
    scheme: HTTPS
  initialDelaySeconds: 30
  periodSeconds: 30

readinessProbe:
  httpGet:
    path: /readiness
    port: 4010
    scheme: HTTPS
  initialDelaySeconds: 5
  periodSeconds: 10
```

#### SSL Certificate Management
```yaml
volumeMounts:
  - name: ssl-certs
    mountPath: /sslcert
    readOnly: true
volumes:
  - name: ssl-certs
    secret:
      secretName: search-api-certs
```

### Monitoring & Observability

#### Prometheus Metrics
```bash
# Key Performance Indicators
search_request_duration_seconds_bucket    # Request latency distribution
search_db_query_duration_seconds         # Database query performance
search_db_connection_failed_total        # Connection failure rate
search_websocket_subscriptions_active    # Real-time connection count
```

#### Logging Configuration
```bash
# Verbosity Levels
klog.V(1) # Error conditions and warnings
klog.V(2) # Important state changes
klog.V(3) # Request/response logging
klog.V(4) # Detailed debugging information
```

#### Alerting Rules
```yaml
groups:
- name: search-api
  rules:
  - alert: SearchAPIHighLatency
    expr: histogram_quantile(0.95, search_request_duration_seconds_bucket) > 5
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Search API 95th percentile latency is high"

  - alert: SearchAPIConnectionFailures
    expr: rate(search_db_connection_failed_total[5m]) > 0.1
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Search API database connection failure rate is high"
```

### Performance Tuning Checklist

#### Database Optimization
- [ ] Connection pool sized for expected concurrent users
- [ ] Database indexes on frequently queried fields (kind, namespace, cluster)
- [ ] VACUUM and ANALYZE scheduled for search.resources table
- [ ] PostgreSQL shared_buffers tuned for available memory

#### Cache Configuration
- [ ] RBAC cache TTL balanced for security vs performance needs
- [ ] Background cache validation enabled in production
- [ ] Cache hit rates monitored via custom metrics

#### Resource Limits
- [ ] Memory limits account for concurrent query processing
- [ ] CPU requests support expected query throughput
- [ ] Network policies allow database and federated cluster access

#### Security Hardening
- [ ] TLS 1.2+ enforced with strong cipher suites
- [ ] Database connections use SSL/TLS
- [ ] ServiceAccount tokens have minimal required permissions
- [ ] Container runs as non-root user (UID 1001)

---

## Quick Reference

### Common Query Patterns
```graphql
# Basic resource search
query BasicSearch {
  search(input: [{
    filters: [
      {property: "kind", values: ["Pod"], operation: "="}
    ]
    limit: 100
  }]) {
    count
    items
  }
}

# Advanced filtering with relationships
query AdvancedSearch {
  search(input: [{
    keywords: ["nginx"]
    filters: [
      {property: "namespace", values: ["default", "web"], operation: "="}
      {property: "status", values: ["Running"], operation: "="}
    ]
    relatedKinds: ["Service", "Deployment"]
    orderBy: "name ASC"
    limit: 50
    offset: 0
  }]) {
    count
    items
    related {
      kind
      count
    }
  }
}
```

### Configuration Quick Setup
```bash
# Minimal development setup
export DB_NAME=searchdb
export DB_USER=postgres
export DB_PASS=password
export FEATURE_FEDERATED_SEARCH=false

# Production recommended
export DB_MAX_CONNS=20
export AUTH_CACHE_TTL=300
export REQUEST_TIMEOUT=180000
export FEATURE_FINE_GRAINED_RBAC=true
```

### Troubleshooting Commands
```bash
# Check API health
curl -k https://localhost:4010/readiness

# View metrics
curl -k https://localhost:4010/metrics | grep search_

# Test GraphQL endpoint
curl -k -X POST https://localhost:4010/searchapi/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"query": "{ messages }"}'
```

This analysis provides comprehensive coverage of the ACM Search API v2 codebase, focusing on practical implementation details for developers working with GraphQL optimization, RBAC integration, and performance tuning.