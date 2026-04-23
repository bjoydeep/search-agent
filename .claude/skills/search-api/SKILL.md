---
name: search-api
description: ACM Search API GraphQL optimization, RBAC patterns, query performance, and client integration strategies  
---

# Search API Deep Dive

## Purpose
The ACM Search API serves as the GraphQL query interface for multi-cluster search capabilities. It provides secure, RBAC-aware access to indexed cluster data with optimized query patterns for ACM dashboards and tooling.

## Role in ACM Search Architecture

### Core Responsibilities  
- **GraphQL Query Processing**: Provides type-safe, efficient GraphQL interface with lazy field resolution
- **RBAC Enforcement**: Implements Kubernetes-native authentication and authorization with intelligent caching
- **Database Query Optimization**: Transforms GraphQL queries into optimized PostgreSQL queries with JSONB support
- **Client Integration**: Serves ACM console, CLI tools, and third-party integrations with consistent API
- **Real-time Updates**: WebSocket subscriptions for live cluster state changes

### Data Flow Position
```
Client Queries → API → Database → Indexer ← Collectors (managed clusters)
```

The API is the primary consumer interface in this flow - its performance directly impacts:
- **User experience**: Dashboard responsiveness and query result latency
- **System capacity**: How many concurrent users and queries the system can handle
- **RBAC overhead**: Authentication and authorization efficiency across large user bases
- **Database pressure**: SQL query patterns and connection pool utilization

## Optimization Focus
This skill covers GraphQL performance optimization, RBAC caching strategies, database query patterns, and client integration approaches. Focuses on architectural principles and performance patterns independent of specific implementation details.

## Core Architecture

### GraphQL Implementation Stack
```
Client Query → gqlgen Framework → Lazy Resolvers → SQL Builder → PostgreSQL
     ↓              ↓                   ↓            ↓           ↓
 Multi-query    Type-safe         Field-level    goqu/v9    JSONB Queries
  Batching      Generation        Resolution     Builder    + Index Opts
```

### Key Optimization Principles
- **Lazy Field Resolution**: Defer expensive operations until explicitly requested by client queries
- **Type-Safe Schema Generation**: Use gqlgen for compile-time GraphQL schema validation and optimization
- **RBAC Cache Hierarchies**: Three-tier caching (token → system → user) for authentication efficiency  
- **SQL Query Builder**: Dynamic, parameterized query generation for security and performance
- **Connection Management**: Efficient database connection pooling and lifecycle management

### Performance Patterns
- **Multi-Query Batching**: Process independent search inputs in single GraphQL operation
- **Recursive Graph Limits**: Configurable depth controls for relationship traversal (apps=3, searches=1)
- **JSONB Query Optimization**: Index-aware property access and containment operations
- **Permission-Aware SQL**: Integrate RBAC filtering at query generation level rather than post-processing

## Optimization Strategies

### GraphQL Query Performance Optimization
**Common Problems:**
- Slow resolver execution affecting user experience
- N+1 query problems with related data loading
- Complex nested queries overwhelming database

**Optimization Patterns:**
- **Field-Level Lazy Loading**: Only resolve requested fields to minimize database queries
- **DataLoader Patterns**: Batch related data fetches to prevent N+1 query scenarios
- **Query Complexity Limits**: Implement depth and complexity analysis to prevent expensive operations
- **Resolver Caching**: Cache frequently accessed data at resolver level

### RBAC and Authentication Optimization
**Common Problems:**
- TokenReview API call overhead for every request
- Permission checks overwhelming Kubernetes API server
- Cache invalidation complexity for user permission changes

**Optimization Patterns:**
- **Token Caching Strategies**: Multi-tier cache with appropriate TTL based on token types
- **Permission Result Caching**: Cache SubjectAccessReview results with namespace-aware expiration
- **Batch Permission Checks**: Group permission validation for efficiency
- **Graceful Degradation**: Handle authentication API failures without complete service disruption

### Database Query Optimization
**Common Problems:**
- Inefficient JSONB queries causing slow response times
- Full table scans for complex filter combinations
- Connection pool exhaustion under concurrent load

**Optimization Patterns:**
- **Index-Aware Query Generation**: Structure SQL to leverage GIN indexes on JSONB properties
- **Parameterized Query Building**: Use type-safe query builders to prevent SQL injection and enable caching
- **Connection Pool Tuning**: Right-size connection pools for concurrent GraphQL query patterns
- **Query Result Pagination**: Efficient offset/limit patterns for large result sets

### Client Integration Optimization
**Common Problems:**
- GraphQL schema evolution breaking client compatibility
- CORS configuration issues affecting browser-based clients
- WebSocket subscription management complexity

**Optimization Patterns:**
- **Schema Versioning**: Backward-compatible GraphQL schema evolution strategies
- **Subscription Lifecycle Management**: Efficient WebSocket connection handling and cleanup
- **Client-Aware Caching**: HTTP cache headers and ETags for efficient client-side caching
- **Error Handling Standards**: Consistent error response format across all client interaction patterns

## Integration Considerations

### **Impact on Database Performance**
- GraphQL query patterns determine database query complexity and load patterns
- RBAC permission checks generate additional database queries for access control
- Client subscription patterns affect database connection pool utilization

### **Dependency on Indexer Data Quality**
- Data freshness depends on indexer processing efficiency and collector synchronization
- Relationship completeness affects GraphQL traversal query results
- Database schema changes require coordinated API schema updates

### **Client Integration Requirements**
- ACM console performance directly correlates with API response times
- CLI tools and automation depend on consistent GraphQL schema evolution
- Third-party integrations require stable API contract and authentication patterns

### **Cross-Cluster Data Access Patterns**
- Multi-cluster queries require efficient cross-cluster relationship handling
- RBAC enforcement must account for cluster-level and namespace-level permissions
- Federation patterns for scaling across very large cluster fleets

## Scaling & Optimization Strategies

### Horizontal Scaling Patterns
- **Stateless API Design**: Enable horizontal scaling through stateless GraphQL processing
- **Load Balancer Configuration**: Distribute client connections efficiently across API replicas
- **Session Affinity**: Handle WebSocket subscriptions with appropriate connection routing
- **Database Connection Distribution**: Coordinate connection pool usage across API replicas

### Performance Tuning Approaches
- **Resolver Optimization**: Minimize database queries through efficient field resolution patterns
- **Cache Strategy Tuning**: Balance cache hit rates with memory utilization and invalidation complexity
- **Query Complexity Management**: Implement client-aware limits based on authentication context
- **Connection Management**: Optimize database connection lifecycle for GraphQL workload patterns

### Capacity Planning
- **User Load Estimation**: Understand relationship between concurrent users and database load
- **Query Pattern Analysis**: Design for common ACM console usage patterns and peak loads
- **RBAC Overhead Planning**: Account for authentication system load in capacity calculations
- **Growth Pattern Design**: Plan for logarithmic scaling as cluster fleet size increases

### Client Performance Considerations
- **GraphQL Query Optimization**: Educate clients on efficient query patterns and field selection
- **Subscription Management**: Design subscription patterns that scale with client connection count
- **Cache Utilization**: Leverage client-side caching for frequently accessed data
- **Error Recovery**: Implement graceful degradation for partial service availability scenarios

---

## Implementation Details

For specific configuration values, file paths, environment variables, and implementation details, see:

**[📋 Code Analysis](code-analysis.md)** - Comprehensive technical implementation guide including:
- GraphQL schema and resolver implementation patterns
- RBAC authentication and caching implementation details  
- Database query optimization and SQL generation specifics
- Performance tuning parameters and configuration options
- Error patterns, debugging approaches, and troubleshooting workflows
- Client integration details and HTTP endpoint specifications