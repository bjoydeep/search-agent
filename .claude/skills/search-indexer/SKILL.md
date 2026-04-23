---
name: search-indexer
description: ACM Search indexer PostgreSQL optimization, batch processing, relationship computation, and scaling strategies
---

# Search Indexer Deep Dive

## Purpose
The ACM Search Indexer serves as the central data processing and storage engine for multi-cluster search capabilities. It receives resource data from search collectors across all managed clusters and processes it into a searchable PostgreSQL database that powers the search API.

## Role in ACM Search Architecture

### Core Responsibilities
- **Data Ingestion**: Receives batched resource updates from search collectors across all managed clusters
- **Relationship Computation**: Analyzes resource relationships and builds cross-cluster dependency graphs
- **Database Management**: Maintains PostgreSQL tables optimized for both storage efficiency and search performance
- **API Backend**: Provides the data layer that powers GraphQL search queries through the search API
- **Hub Integration**: Synchronizes hub-level resources (ManagedCluster, policies) with managed cluster data

### Data Flow Position
```
Collectors (managed clusters) → Indexer (hub) → Database → Search API → Users
```

The indexer is the critical bottleneck in this flow - its performance directly impacts:
- **Data freshness**: How quickly cluster changes appear in search results
- **Search performance**: How fast the API can respond to queries
- **System capacity**: How many clusters and resources the search system can handle

## Optimization Focus
This skill covers optimization strategies and PostgreSQL scaling patterns for multi-cluster search workloads. Focuses on architectural principles, performance optimization patterns, and scaling strategies independent of specific implementation details.

## Core Architecture

### Dual-Table PostgreSQL Design
```
search.resources (JSONB documents)     search.edges (relationship mappings)
├─ Flexible schema evolution           ├─ Optimized relationship queries
├─ GIN indexes on JSONB paths         ├─ B-tree indexes on cluster columns
├─ Efficient document storage         └─ Cross-cluster relationship computation
└─ Property access optimization
```

### Key Optimization Principles
- **Connection Pooling Strategy**: Right-size connection pools to match concurrent load patterns without overwhelming PostgreSQL
- **Batch Processing Design**: Use optimal batch sizes that balance throughput with memory usage and transaction isolation
- **Conditional Upserts**: Avoid unnecessary database writes by checking data equality before updates
- **In-Memory Caching**: Cache frequently accessed metadata to reduce database round trips
- **Request Limiting**: Implement tiered concurrency controls for different request sizes and processing complexity

### Performance Patterns
- **Connection Lifecycle Management**: Balance connection reuse with resource cleanup through appropriate lifecycle limits
- **Fleet Synchronization Prevention**: Add jitter to prevent all collectors from hitting the database simultaneously
- **Single-Writer Architecture**: Use leader election for stateful operations that require consistency across the cluster
- **Graceful Backoff**: Implement exponential backoff with reasonable limits to handle temporary database pressure

## Optimization Strategies

### Database Performance Optimization
**Common Problems:**
- Write performance degradation during peak synchronization periods
- Connection pool exhaustion under concurrent load
- Query timeouts affecting API layer responsiveness

**Optimization Patterns:**
- **Index Strategy**: Use GIN indexes for JSONB search patterns, B-tree indexes for cluster-based queries
- **Connection Pool Sizing**: Balance pool size with PostgreSQL max_connections and expected concurrent load
- **Query Optimization**: Structure queries to leverage prepared statements and index scan patterns
- **Write Batching**: Group related operations to minimize transaction overhead

### Batch Processing Optimization
**Common Problems:**
- Memory pressure from large batch operations
- Processing timeouts during cluster synchronization
- Retry storms causing cascading failures

**Optimization Patterns:**
- **Adaptive Batch Sizing**: Adjust batch sizes based on resource complexity and available memory
- **Binary Search Recovery**: When batches fail, use binary search to identify optimal sub-batch sizes
- **Memory Management**: Implement garbage collection triggers for large processing operations
- **Graceful Degradation**: Reduce batch sizes automatically under resource pressure

### Relationship Computation Optimization
**Common Problems:**
- Missing or inconsistent cross-cluster relationships
- Slow graph traversal for complex relationship queries
- Edge computation latency affecting search performance

**Optimization Patterns:**
- **Incremental Computation**: Only recompute relationships for changed resources
- **Edge Caching**: Cache computed relationships to avoid redundant calculations
- **Parallel Processing**: Compute relationships concurrently for independent resource sets
- **Consistency Validation**: Regular verification of resource-edge data alignment

## Integration Considerations

### **Impact on API Performance**
- Database query patterns directly affect GraphQL response times
- Connection pool exhaustion cascades to API layer availability
- Index optimization strategies should align with common search patterns

### **Collector Synchronization Dependencies**
- Batch processing capabilities determine collector sync success rates
- Request limiting affects collector backoff and retry patterns
- Network optimization impacts cross-cluster data synchronization

### **Hub Resource Integration**
- Leader election design affects hub resource processing consistency
- Informer patterns determine managed cluster data freshness
- Resource reconciliation strategies impact overall search completeness

## Scaling & Optimization Strategies

### Database Scaling Patterns
- **Vertical Scaling**: Scale PostgreSQL resources based on write-heavy workload characteristics
- **Connection Pool Design**: Size pools to balance concurrency with database connection limits  
- **Index Strategy**: Choose between GIN indexes for flexible search and B-tree indexes for structured queries
- **Partitioning**: Consider table partitioning strategies for very large multi-cluster deployments

### Performance Tuning Approaches
- **Adaptive Batch Sizing**: Tune batch sizes based on cluster scale and resource complexity
- **Connection Lifecycle Management**: Balance connection reuse with resource cleanup requirements
- **Fleet Coordination**: Implement jitter and backoff to prevent synchronized load patterns
- **Memory Management**: Optimize garbage collection timing for batch processing workloads

### Capacity Planning
- **Load Estimation**: Understand relationship between cluster count, resource density, and database load
- **Growth Patterns**: Design for logarithmic growth in relationship computation as fleet size increases
- **Resource Requirements**: Plan CPU, memory, and storage based on write-heavy workload patterns
- **Monitoring Strategy**: Establish baselines for normal operation to detect scaling needs early

---

## Implementation Details

For specific configuration values, file paths, environment variables, and implementation details, see:

**[📋 Code Analysis](code-analysis.md)** - Comprehensive technical implementation guide including:
- PostgreSQL connection pooling configuration and tuning
- Batch processing implementation with specific parameters  
- Environment variables and configuration options
- Error patterns, debugging approaches, and troubleshooting
- Deployment configuration and resource requirements
- API endpoints, metrics, and integration interfaces