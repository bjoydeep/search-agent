---
name: search-api
description: ACM Search API GraphQL optimization, RBAC patterns, query performance, and client integration
---

# Search API Deep Dive

## Source Code Repository
**GitHub**: https://github.com/stolostron/search-v2-api

### Key Source Files & Patterns
- **GraphQL schema & resolvers**: `pkg/resolver/` - Type-safe schema generation and query resolution
- **Authentication & RBAC**: `pkg/rbac/` - TokenReview, SSAR/SSRR integration, and caching
- **Database queries**: `pkg/database/` - SQL query generation and optimization
- **HTTP server**: `pkg/server/` - GraphQL endpoint and middleware
- **Configuration**: `cmd/main.go` - Server startup and authentication configuration

### Code Exploration Tips
- Start with `cmd/main.go` for server initialization and auth setup
- Review `pkg/resolver/` for GraphQL resolver patterns and lazy loading
- Check `pkg/rbac/` for RBAC caching strategies and Kubernetes integration
- Look at `pkg/database/query_builder.go` for SQL generation patterns

## Current API Status
- Active queries being served: !`find_resources --outputMode=count` total resources available
- Recent query activity: !`find_resources --ageNewerThan=1h --outputMode=count --groupBy=cluster`
- Resource type distribution: !`find_resources --outputMode=count --groupBy=kind --limit=15`
- Current fleet accessibility: !`find_resources --kind=ManagedCluster --outputMode=count --groupBy=status`

## Core Architecture

### GraphQL Implementation Stack
```
Client Query → gqlgen Framework → Lazy Resolvers → SQL Builder → PostgreSQL
     ↓              ↓                   ↓            ↓           ↓
 Multi-query    Type-safe         Field-level    goqu/v9    JSONB Queries
  Batching      Generation        Resolution     Builder    + Index Opts
```

### Technical Implementation
- **gqlgen Framework**: Type-safe GraphQL schema generation with automatic resolver binding
- **Lazy Field Resolution**: `SearchResult` struct encapsulates query state, resolvers defer execution
- **Multi-Query Batching**: Independent search inputs with different filters/keywords/limits
- **SQL Query Builder**: goqu/v9 dynamic, type-safe query construction
- **Recursive CTEs**: Configurable depth graph traversal (apps=3, searches=1)

### RBAC & Authentication
- **TokenReview API**: Kubernetes-native stateless authentication with token caching
- **Three-Tier RBAC Cache**: Token cache + shared system cache + user-specific cache
- **SSAR/SSRR Integration**: Native Kubernetes permission determination via SubjectAccessReview
- **Complex WHERE Clauses**: Four-layer permission enforcement with cluster admin bypass

## Common Issues & Solutions

### GraphQL Query Performance
**Symptoms:**
- Slow API response times
- GraphQL query timeouts
- High database load from API queries

**Diagnostic Commands:**
```bash
# API pod status and resource usage
kubectl get pods -l component=search-api -o wide
kubectl top pods -l component=search-api

# GraphQL query performance and errors
kubectl logs -l component=search-api --tail=200 | grep -E "(query|resolver|timeout|error)"

# Database query patterns from API
kubectl logs -l component=search-api --tail=100 | grep -E "(sql|database|postgres)"

# Response time analysis
kubectl logs -l component=search-api --tail=200 | grep -E "(duration|latency|response)"
```

**Common Causes:**
- [TODO: Add GraphQL query optimization patterns]
- [TODO: Add resolver performance tuning strategies]
- [TODO: Add database query optimization for API patterns]

### RBAC & Authentication Issues
**Symptoms:**
- Authorization failures for valid users
- Missing resources in search results
- Token validation errors

**Diagnostic Commands:**
```bash
# RBAC cache performance and auth errors
kubectl logs -l component=search-api --tail=200 | grep -E "(rbac|auth|token|permission)"

# TokenReview API calls and caching
kubectl logs -l component=search-api --tail=100 | grep -E "(TokenReview|SubjectAccessReview|cache)"

# User permission validation
kubectl logs -l component=search-api --tail=300 | grep -E "(SSAR|SSRR|ClusterRole|namespace)"
```

**Authentication Patterns:**
- [TODO: Add TokenReview optimization and caching strategies]
- [TODO: Add RBAC troubleshooting for missing resource access]
- [TODO: Add permission debugging workflows]

### Client Integration Problems
**Symptoms:**
- Connection failures from ACM UI
- Inconsistent search results across clients
- Client timeout errors

**Diagnostic Commands:**
```bash
# HTTP connection and client errors
kubectl logs -l component=search-api --tail=200 | grep -E "(http|client|connection|cors)"

# GraphQL schema and introspection issues
kubectl logs -l component=search-api --tail=100 | grep -E "(schema|introspection|mutation)"

# Load balancing and service health
kubectl get svc search-api -o yaml
kubectl get endpoints search-api
```

**Integration Patterns:**
- [TODO: Add client integration debugging patterns]
- [TODO: Add CORS and HTTP configuration troubleshooting]
- [TODO: Add GraphQL schema evolution and compatibility]

### Query Optimization Issues
**Symptoms:**
- Complex queries causing high database load
- Pagination performance problems
- Graph traversal timeouts

**Diagnostic Commands:**
```bash
# Complex query analysis
kubectl logs -l component=search-api --tail=300 | grep -E "(depth|traversal|recursive|CTE)"

# Pagination and result set performance
kubectl logs -l component=search-api --tail=200 | grep -E "(limit|offset|pagination|batch)"

# Query builder and SQL generation
kubectl logs -l component=search-api --tail=200 | grep -E "(goqu|builder|WHERE|JOIN)"
```

**Optimization Strategies:**
- [TODO: Add graph traversal depth optimization]
- [TODO: Add pagination performance tuning]
- [TODO: Add query complexity analysis and limits]

## Live API Performance Analysis

### GraphQL Query Monitoring
```bash
# Active GraphQL operations and performance
kubectl exec -it $(kubectl get pods -l component=search-api -o name | head -1) -- curl localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "query { __schema { queryType { name } } }"}'

# Query complexity and execution time analysis
kubectl logs -l component=search-api --tail=500 | grep -E "duration" | sort -k3 -nr | head -10
```

### RBAC Cache Performance
```bash
# RBAC cache hit rates and performance
kubectl logs -l component=search-api --tail=300 | grep -E "(cache|hit|miss)" | tail -20

# TokenReview API call frequency
kubectl logs -l component=search-api --tail=200 | grep "TokenReview" | wc -l
```

### Database Query Analysis
```bash
# API-generated SQL query patterns
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -d search -c "
SELECT substring(query for 100) as query_start, calls, total_time, mean_time
FROM pg_stat_statements
WHERE query LIKE '%data->>%' OR query LIKE '%@>%'
ORDER BY total_time DESC LIMIT 10;"
```

## Cross-Component Routing

### **Database performance affecting queries** → `/search-indexer`
- Slow PostgreSQL queries requiring index optimization
- Connection pool exhaustion from API load
- JSONB query patterns needing database tuning

### **Missing or stale data** → `/search-collector`
- Resource discovery issues causing incomplete API results
- Collector connectivity affecting data freshness
- Cross-cluster relationship gaps in API responses

### **Deployment and configuration** → `/search-operator`
- API pod deployment and scaling configuration
- Service exposure and load balancing setup
- RBAC policy configuration for API access

### **Overall system performance** → `/search-performance`
- API scaling decisions based on client load
- GraphQL query performance optimization
- Client integration performance analysis

## GraphQL Schema & Query Patterns

### Schema Design Patterns
- **Lazy field resolution**: Efficient data loading only when fields are requested
- **Multi-input queries**: Batching multiple search requests in single GraphQL call
- **Recursive relationships**: Graph traversal with configurable depth limits
- **Flexible filtering**: Dynamic WHERE clause generation from GraphQL inputs

### Query Optimization
- **Index-friendly patterns**: Property access via `data->>'property'` for string types
- **JSONB containment**: Efficient filtering using `@>` containment operators
- **Operator-aware SQL**: String LIKE, numeric casting, JSONB path operations
- **Permission integration**: RBAC enforcement at SQL generation level

### Performance Monitoring
- **Query complexity analysis**: Depth limits and field counting
- **Execution time tracking**: Query-level performance measurement
- **Cache utilization**: RBAC cache hit rates and effectiveness
- **Database query patterns**: SQL generation optimization

---

## TODO: Questions for Enhancement

Please help enhance this skill by answering:

### **1. GraphQL Performance Issues?**
- What are your most common GraphQL query performance problems?
- Optimization strategies for complex nested queries?
- Query complexity limits and depth restrictions you've implemented?

### **2. RBAC & Authentication Patterns?**
- Common authentication failures and their root causes?
- RBAC cache optimization strategies for large user bases?
- TokenReview API performance tuning approaches?

### **3. Client Integration Challenges?**
- ACM UI integration issues and resolution patterns?
- API versioning and compatibility strategies?
- CORS and HTTP configuration best practices?

### **4. Database Query Optimization?**
- PostgreSQL query patterns that work best with JSONB data?
- Index strategies for common GraphQL query patterns?
- Connection pooling optimization for API load?

### **5. Scaling & Load Management?**
- API horizontal scaling strategies and load balancing?
- Query rate limiting and throttling approaches?
- Performance benchmarks for different fleet sizes?

### **6. Graph Traversal & Relationships?**
- Optimization for complex relationship queries?
- Recursive CTE performance tuning?
- Cross-cluster relationship query patterns?

Please update this skill with your API optimization experience and GraphQL performance patterns!

---

## Code Analysis & Implementation Details

**[📋 Code Analysis](code-analysis.md)** - Comprehensive source code analysis including:
- GraphQL schema and resolver patterns
- RBAC implementation and caching strategies
- Database query optimization and SQL generation
- Performance tuning parameters and configuration
- Error patterns and debugging workflows
- Client integration and HTTP endpoint details