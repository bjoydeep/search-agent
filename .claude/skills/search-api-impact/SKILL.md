---
name: search-api-impact
description: Assess search API query latency, RBAC load, and response time degradation when policies are deployed, clusters are added, or API server experiences load. Use for policy deployment events, query performance issues, RBAC authentication problems, or GraphQL response delays.
---

# Search API Impact Assessment

## Purpose
Specialized assessment of search API performance impact when ACM policies are deployed, clusters are added, or API server experiences load. Focuses on GraphQL query latency, RBAC authentication overhead, concurrent connection handling, and response time degradation patterns.

## When to Use
- **Policy deployment events**: New governance policies affecting search queries
- **Query performance degradation**: Slow GraphQL response times
- **RBAC authentication issues**: Role-based access control overhead
- **High concurrent load**: Multiple users/systems querying simultaneously
- **API server resource pressure**: Memory or CPU constraints affecting responses

## Available API Monitoring

The search-v2-api provides comprehensive monitoring through **7 Prometheus metrics** and **extensive health endpoints**:

### Prometheus Metrics (Port 4010)

### Core Metrics
1. **`search_api_request_duration`** (Histogram with labels)
   - **Purpose**: Time (seconds) the search API took to process requests
   - **Labels**: `code` (HTTP response), `remoteAddr` (client IP), `userAgent` (client browser/tool)
   - **Usage**: Monitor GraphQL request latency and identify user patterns

2. **`search_api_db_connection_failed`** (Counter)
   - **Purpose**: Number of failed database connection attempts
   - **Usage**: Track database connectivity issues affecting API availability

3. **`search_api_db_query_duration`** (Histogram with labels)
   - **Purpose**: Latency (seconds) for database queries
   - **Labels**: `query_name` (e.g., "resolveItemsFunc")
   - **Usage**: Monitor specific database query performance in GraphQL resolvers

4. **`search_api_subscriptions_active`** (Gauge)
   - **Purpose**: Number of active WebSocket subscriptions
   - **Usage**: Monitor real-time usage and concurrent subscription load

5. **`search_api_subscription_duration`** (Histogram)
   - **Purpose**: Duration (seconds) of WebSocket subscriptions
   - **Usage**: Track WebSocket session lifetime patterns

6. **`search_api_websocket_connections_total`** (Counter)
   - **Purpose**: Total number of WebSocket connection attempts
   - **Usage**: Monitor real-time feature adoption and connection volume

7. **`search_api_websocket_connections_failed`** (Counter with labels)
   - **Purpose**: Number of failed WebSocket connection attempts
   - **Labels**: `reason` ("missing_token", "auth_error", "invalid_token", "websocket_error")
   - **Usage**: Track authentication and connection failures by type

### Additional Health Endpoints
- **`/liveness`**: Basic liveness probe (returns "OK")
- **`/readiness`**: Basic readiness probe (returns "OK")  
- **`/metrics`**: Prometheus metrics endpoint (port 4010)

## Assessment Methodology

The API impact assessment is implemented as a set of modular scripts that can be executed independently or as a coordinated suite. This separation of concerns follows our established design principles.

### Core Implementation Scripts

**1. Prometheus API Metrics Collection (Weight: 60%)**
- **Script**: `scripts/prometheus-metrics.sh`
- **Purpose**: Collect comprehensive API metrics from OpenShift Prometheus monitoring
- **Features**: Advanced/fallback query patterns, API-specific metrics focus
- **Outputs**: Request duration percentiles, database query performance, WebSocket health, error rates

**2. User Pattern Analysis (Weight: 25%)**
- **Script**: `scripts/user-pattern-analysis.sh`
- **Purpose**: Analyze performance patterns by client type and usage patterns
- **Features**: Direct `/metrics` endpoint access, user agent classification, request source analysis
- **Outputs**: Client type breakdown (Dashboard vs CLI vs Automation), error rates by user type, geographical patterns

**3. Database and WebSocket Health Analysis (Weight: 10%)**
- **Script**: `scripts/database-websocket.sh`
- **Purpose**: Monitor database connectivity and real-time feature health
- **Features**: Health endpoint monitoring, resource utilization tracking, database connection analysis
- **Outputs**: Health probe status, resource consumption, database connection state

**4. RBAC Authentication Analysis (Weight: 5%)**
- **Script**: `scripts/rbac-analysis.sh`
- **Purpose**: Assess authentication overhead and RBAC complexity impact
- **Features**: Multi-window log analysis, policy complexity assessment, authentication timing
- **Outputs**: Authentication event patterns, RBAC error analysis, policy complexity metrics

### Orchestration and Execution

**Main Assessment Script**
- **Script**: `scripts/generate-assessment.sh`
- **Purpose**: Coordinate all assessment components and generate final report
- **Features**: Script orchestration, metrics aggregation, comprehensive audit logging
- **Outputs**: Structured assessment report with execution audit trail

### Usage

**Execute Full Assessment:**
```bash
cd .claude/skills/search-api-impact
./scripts/generate-assessment.sh
```

**Execute Individual Components:**
```bash
# Prometheus metrics only
./scripts/prometheus-metrics.sh

# User pattern analysis only
./scripts/user-pattern-analysis.sh

# Database and WebSocket health only
./scripts/database-websocket.sh

# RBAC analysis only
./scripts/rbac-analysis.sh
```

### Performance Thresholds

**GraphQL Query Response Time Levels:**
- **Normal**: <500ms for basic queries, <2s for complex queries
- **Warning**: 500ms-2s for basic, 2s-5s for complex queries
- **Critical**: >2s for basic queries, >5s for complex queries

**RBAC Authentication Load Levels:**
- **Normal**: <100 RBAC evaluations per minute
- **Warning**: 100-300 RBAC evaluations per minute  
- **Critical**: >300 RBAC evaluations per minute

**Resource Utilization Levels:**
- **Normal**: <70% CPU and memory usage
- **Warning**: 70-85% resource usage
- **Critical**: >85% resource usage

**Database Query Performance Levels:**
- **Normal**: <50ms average database query time
- **Warning**: 50-100ms average database query time
- **Critical**: >100ms average database query time

**WebSocket Connection Health:**
- **Normal**: <5% WebSocket connection failure rate
- **Warning**: 5-15% connection failure rate
- **Critical**: >15% connection failure rate

### Confidence Scoring Algorithm

```python
def calculate_api_confidence(response_time, rbac_load, resource_usage, query_complexity, websocket_health):
    # Normalize metrics to 0.0-1.0 scale where 1.0 = critical
    response_score = min(response_time / 2000.0, 1.0)  # 2000ms = critical for basic queries
    rbac_score = min(rbac_load / 300.0, 1.0)  # 300 evals/min = critical
    resource_score = min(resource_usage / 85.0, 1.0)  # 85% = critical
    query_score = min(query_complexity / 100.0, 1.0)  # 100ms avg = critical
    websocket_score = min(websocket_health / 15.0, 1.0)  # 15% failure rate = critical
    
    # Apply weights: response time (40%), RBAC (25%), resources (15%), DB queries (15%), WebSocket (5%)
    confidence_score = (response_score * 0.4) + (rbac_score * 0.25) + (resource_score * 0.15) + (query_score * 0.15) + (websocket_score * 0.05)
    
    return confidence_score
```

## Output Format

**Save assessment results to:** `monitoring_data/impacts/{hub_cluster_id}_api_impact.json`

**Hub cluster identification:**
```bash
# Get hub cluster ID from ManagedCluster CR
HUB_CLUSTER_ID=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.clusterID}')
HUB_OCP_VERSION=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.openshiftVersion-major-minor}')
```

The assessment generates a comprehensive JSON report with the following key sections:
- **Assessment metadata**: Type, scope, hub cluster information
- **Confidence scoring**: Overall health assessment and contributing factors
- **Raw metrics**: Detailed API performance, user patterns, and authentication metrics
- **Recommendations**: Specific actions based on assessment findings
- **Execution audit trail**: Complete transparency into data collection operations

## Architectural Context

### API Impact Chain
```
Policy Deployment → RBAC Complexity → Authentication Overhead → Query Latency → User Impact
```

### Common Impact Patterns
- **Policy proliferation**: More policies increase RBAC evaluation complexity
- **Large cluster additions**: More data increases query execution time
- **Concurrent user load**: Multiple dashboards/tools overwhelming API
- **Complex queries**: Multi-cluster filters with large result sets
- **WebSocket subscription growth**: Real-time feature adoption affecting resource usage

### Integration Points
- **With search-indexer-impact**: Database pressure affects query performance
- **With search-collector-impact**: Data freshness affects query results
- **With policy deployment systems**: Understanding governance load impact

## Tools Available
- **Bash**: Execute kubectl and curl commands for metrics collection
- **Write**: Save assessment results and performance analysis
- **Read**: Access previous assessments and configuration data

## Critical Success Factors
- **Real-time response monitoring**: Catch query latency degradation early
- **RBAC overhead tracking**: Authentication complexity is key bottleneck
- **User pattern recognition**: Different client types have different performance expectations
- **Resource scaling awareness**: Know when to scale API server horizontally
- **Query optimization focus**: Complex queries disproportionately impact performance
- **WebSocket health monitoring**: Real-time features require special attention

## Design Benefits

### Separation of Concerns
- **Methodology vs Implementation**: SKILL.md focuses on WHAT to monitor and WHY
- **Modular Scripts**: Each script has a single responsibility and can be tested independently
- **Maintainability**: Script bugs don't require skill updates; methodology changes don't affect implementations

### Reusability
- **Independent Execution**: Scripts can be used by other monitoring tools
- **Composable Assessment**: Different combinations of scripts for different scenarios  
- **Integration Ready**: Scripts output structured data for automated processing

### Testing and Debugging
- **Script-level Testing**: Each component can be validated separately
- **Error Isolation**: Issues can be traced to specific assessment components
- **Development Workflow**: Scripts can be iterated without affecting skill definitions
- **Comprehensive Audit Trails**: Every operation logged with timestamps and raw responses

### Advanced Capabilities
- **Multi-source Data Collection**: Prometheus metrics, direct API endpoints, health probes, RBAC logs
- **Advanced/Fallback Patterns**: Graceful degradation when advanced queries fail
- **User Pattern Recognition**: Automatic classification of client types and behavior analysis
- **Time-window Analysis**: Multi-timeframe RBAC and authentication analysis
- **Complete Transparency**: Full execution audit trail for debugging and validation