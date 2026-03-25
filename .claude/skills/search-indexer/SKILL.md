---
name: search-indexer
description: ACM Search indexer PostgreSQL optimization, batch processing, relationship computation, and scaling strategies
---

# Search Indexer Deep Dive

## Source Code Repository
**GitHub**: https://github.com/stolostron/search-indexer

### Key Source Files & Patterns
- **Main indexer logic**: `pkg/indexer/` - PostgreSQL batch processing and relationship computation
- **Database layer**: `pkg/database/` - Connection pooling, queries, and schema management
- **Cluster sync**: `pkg/reconciler/` - Collector data processing and hub resource integration
- **HTTP server**: `pkg/server/` - REST endpoints for collector sync and health checks
- **Configuration**: `cmd/main.go` - Startup, database connection, and configuration management

### Code Exploration Tips
- Start with `cmd/main.go` for initialization and database connection setup
- Review `pkg/indexer/indexer.go` for core batch processing logic
- Check `pkg/database/` for PostgreSQL interaction patterns
- Look at `pkg/reconciler/` for collector data integration and hub resource handling

## Current Indexer Status
- Database size and health: !`find_resources --outputMode=summary`
- Recent indexing activity: !`find_resources --ageNewerThan=1h --outputMode=count --groupBy=cluster`
- Resource growth trends: !`find_resources --ageNewerThan=24h --outputMode=count --groupBy=kind --limit=15`
- Cross-cluster relationship coverage: !`find_resources --outputMode=count --groupBy=cluster --limit=10`

## Core Architecture

### Dual-Table PostgreSQL Design
```
search.resources (JSONB documents)     search.edges (relationship mappings)
├─ Flexible schema evolution           ├─ Optimized relationship queries
├─ GIN indexes on JSONB paths         ├─ B-tree indexes on cluster columns
├─ Efficient document storage         └─ Cross-cluster relationship computation
└─ Property access optimization
```

### Technical Implementation
- **Connection Pooling**: pgxpool with 2-10 connections, 5-minute lifecycle limits
- **Batch Processing**: 2,500 operations per batch with binary-search retry splitting
- **Conditional Upserts**: `INSERT ON CONFLICT DO UPDATE WHERE data!=$3` prevents unnecessary writes
- **In-Memory Caching**: `existingClustersCache` avoids redundant database queries
- **Concurrency Control**: 25 general concurrent requests, 5 large requests (>20MB)

### Performance Characteristics
- **Connection Management**: Health checks at `afterConnect()` and `beforeAcquire()` callbacks
- **Jitter Prevention**: 1-minute connection jitter prevents fleet synchronization issues
- **Leader Election**: Kubernetes-native single-instance processing prevents data conflicts
- **Exponential Backoff**: Max 5-minute backoff with configurable `MaxBackoffMS`

## Common Issues & Solutions

### Database Performance Problems
**Symptoms:**
- Slow write performance during peak sync
- Connection pool exhaustion
- Query timeouts from API layer

**Diagnostic Commands:**
```bash
# Indexer pod status and resource usage
kubectl get pods -l component=search-indexer -o wide
kubectl top pods -l component=search-indexer

# Database connection and performance metrics
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -c "
SELECT datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit,
       temp_files, temp_bytes, deadlocks, conflicts
FROM pg_stat_database WHERE datname = 'search';"

# Connection pool status and active queries
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -c "
SELECT state, count(*) FROM pg_stat_activity WHERE datname = 'search' GROUP BY state;"

# Table sizes and index usage
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -d search -c "
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables WHERE schemaname = 'search';"
```

**Common Causes:**
- [TODO: Add PostgreSQL tuning parameters for search workload]
- [TODO: Add index optimization strategies]
- [TODO: Add connection pool sizing recommendations]

### Batch Processing Issues
**Symptoms:**
- Sync failures from collectors
- High memory usage during large batch processing
- Timeout errors in indexer logs

**Diagnostic Commands:**
```bash
# Indexer batch processing logs
kubectl logs -l component=search-indexer --tail=200 | grep -E "(batch|processing|upsert|conflict)"

# Memory usage and garbage collection patterns
kubectl logs -l component=search-indexer --tail=100 | grep -E "(memory|GC|heap)"

# Failed batch operations and retries
kubectl logs -l component=search-indexer --tail=500 | grep -E "(error|retry|timeout|failed)"
```

**Performance Tuning:**
- [TODO: Add batch size optimization based on cluster scale]
- [TODO: Add retry strategy configuration]
- [TODO: Add memory management patterns for large syncs]

### Relationship Computation Problems
**Symptoms:**
- Missing cross-cluster relationships in search results
- Inconsistent edge data between resources and edges tables
- Slow graph traversal queries

**Diagnostic Commands:**
```bash
# Check relationship computation logs
kubectl logs -l component=search-indexer --tail=300 | grep -E "(edge|relationship|graph|compute)"

# Validate relationship data consistency
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -d search -c "
SELECT 'Resources' as table, count(*) as count FROM search.resources
UNION SELECT 'Edges' as table, count(*) as count FROM search.edges;"

# Cross-cluster relationship distribution
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -d search -c "
SELECT edgetype, count(*) FROM search.edges GROUP BY edgetype ORDER BY count DESC;"
```

**Analysis Patterns:**
- [TODO: Add relationship consistency validation queries]
- [TODO: Add cross-cluster relationship troubleshooting]
- [TODO: Add edge computation performance optimization]

### Hub Resource Integration Issues
**Symptoms:**
- Missing ManagedCluster, ManagedClusterInfo resources
- Inconsistent hub vs managed cluster data
- Stale hub resource information

**Diagnostic Commands:**
```bash
# Hub informer status and recent activity
kubectl logs -l component=search-indexer --tail=200 | grep -E "(hub|informer|ManagedCluster)"

# Hub vs collector data consistency
kubectl get managedclusters --no-headers | wc -l  # Hub count
# Compare with: !`find_resources --kind=ManagedCluster --outputMode=count`

# Recent hub resource updates
kubectl get events --field-selector involvedObject.kind=ManagedCluster --sort-by=.lastTimestamp | tail -10
```

**Integration Patterns:**
- [TODO: Add hub informer troubleshooting patterns]
- [TODO: Add managed cluster lifecycle handling]
- [TODO: Add hub resource sync validation]

## Live Database Analysis

### Performance Monitoring
```bash
# Database query performance analysis
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -d search -c "
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
WHERE query LIKE '%search.resources%' OR query LIKE '%search.edges%'
ORDER BY total_time DESC LIMIT 10;"

# Index usage and effectiveness
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -d search -c "
SELECT schemaname, tablename, indexname, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes WHERE schemaname = 'search';"
```

### Capacity Planning
```bash
# Database growth trends
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -d search -c "
SELECT
  COUNT(*) as total_resources,
  COUNT(DISTINCT cluster) as clusters,
  AVG(LENGTH(data::text)) as avg_document_size
FROM search.resources;"

# Connection pool utilization
kubectl logs -l component=search-indexer --tail=100 | grep -E "(connection|pool|acquire)"
```

## Cross-Component Routing

### **Database performance affecting API** → `/search-api`
- Slow queries impacting GraphQL response times
- Connection pool exhaustion affecting API availability
- Index optimization needed for common query patterns

### **Collector sync failures** → `/search-collector`
- HTTP sync timeouts or connection issues
- Batch processing rejections causing collector backoff
- Network connectivity problems between collectors and indexer

### **Hub resource integration** → `/search-operator`
- ManagedCluster informer configuration issues
- Addon status not reflecting indexer health
- Leader election problems affecting hub resource processing

### **System scaling decisions** → `/search-performance`
- Database scaling based on fleet growth
- Connection pool sizing for cluster count
- Performance optimization strategies for large deployments

## Scaling & Optimization Strategies

### Database Scaling Patterns
- **Vertical scaling**: CPU and memory optimization for PostgreSQL workload
- **Connection pooling**: Optimal pool sizing based on concurrent collectors
- **Index strategy**: GIN vs B-tree optimization for hybrid workload
- **Partitioning**: Strategies for very large resource datasets

### Performance Tuning
- **Batch size optimization**: 2,500 operations vs smaller/larger batches
- **Connection lifecycle**: 5-minute vs longer connection lifetimes
- **Jitter configuration**: Connection timing to prevent fleet synchronization
- **Memory management**: Go GC tuning for batch processing workloads

---

## TODO: Questions for Enhancement

Please help enhance this skill by answering:

### **1. Database Performance Issues?**
- What are your most common PostgreSQL performance problems with search indexer?
- Query optimization patterns you've implemented?
- Connection pool sizing strategies based on fleet size?

### **2. Batch Processing Patterns?**
- How do you tune batch sizes for different cluster scales?
- Memory management strategies for large batch processing?
- Retry and error handling patterns for failed batches?

### **3. Scaling Strategies?**
- How do you scale the indexer for large fleets (100+ clusters)?
- Database partitioning or sharding strategies you've considered?
- Performance benchmarks and capacity planning approaches?

### **4. Relationship Computation?**
- Common issues with cross-cluster relationship computation?
- Performance optimization for graph traversal queries?
- Consistency validation and troubleshooting approaches?

### **5. Hub Resource Integration?**
- Hub informer configuration and optimization patterns?
- ManagedCluster lifecycle handling best practices?
- Leader election issues and resolution strategies?

### **6. Monitoring & Diagnostics?**
- Key PostgreSQL metrics you monitor for search workload?
- Alerting thresholds for indexer performance?
- Log analysis patterns for troubleshooting indexer issues?

Please update this skill with your operational experience and database optimization patterns!

---

## Code Analysis & Implementation Details

**[📋 Code Analysis](code-analysis.md)** - Comprehensive source code analysis including:
- PostgreSQL connection pooling and database patterns
- Batch processing implementation and optimization
- Configuration options and performance tuning
- Error patterns and troubleshooting guidance
- Component deployment and scaling strategies
- Integration interfaces and API endpoints

*Note: This code analysis is currently a placeholder and needs completion for the indexer repository.*