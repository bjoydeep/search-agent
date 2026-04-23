---
name: search-indexer-impact
description: Comprehensive indexer performance assessment combining Prometheus metrics with deep PostgreSQL diagnostics. Analyze request processing, database pressure, resource distribution, and relationship computation efficiency. Use for ManagedCluster events, indexer performance issues, database connection problems, or processing degradation.
---

# Search Indexer Impact Assessment

## Purpose
Specialized assessment of search indexer performance impact when ACM managed clusters change or indexer components experience stress. Focuses on PostgreSQL database pressure, resync frequency patterns, batch processing efficiency, and relationship computation performance.

## When to Use
- **ManagedCluster events**: New clusters causing indexer load spikes
- **Indexer restarts**: Component failures or configuration changes
- **Resync storms**: Abnormally high resync frequency patterns
- **Database performance issues**: PostgreSQL connection or query problems
- **Batch processing delays**: Slow relationship computation or data ingestion

## Available Indexer Monitoring

The search-indexer provides comprehensive monitoring through **4 Prometheus metrics** and **extensive PostgreSQL diagnostics**:

### Prometheus Metrics (Port 3010)

### Core Metrics
1. **`search_indexer_request_count`** (Counter with `managed_cluster_name` label)
   - **Purpose**: Total requests received by search indexer from managed clusters  
   - **Labels**: `managed_cluster_name` (e.g., "local-cluster", "production-east")
   - **Usage**: Monitor sync request rate per cluster

2. **`search_indexer_request_duration`** (Histogram with `code` label)
   - **Purpose**: Time (seconds) indexer takes to process sync requests
   - **Labels**: `code` (HTTP response codes: "200", "400", "500", etc.)
   - **Buckets**: `[0.25, 0.5, 1, 1.5, 2, 3, 5, 10]` seconds
   - **Usage**: Track processing latency and error rates

3. **`search_indexer_requests_in_flight`** (Gauge)
   - **Purpose**: Total requests indexer is processing at a given time
   - **Usage**: Monitor concurrent processing load and capacity utilization

4. **`search_indexer_request_size`** (Histogram) 
   - **Purpose**: Total changes (add, update, delete) per sync request
   - **Buckets**: `[50, 100, 200, 500, 5000, 10000, 25000, 50000, 100000, 200000]` changes
   - **Usage**: Analyze payload size distribution and processing complexity

### Additional Health Endpoints
- **`/liveness`**: Basic liveness probe (returns "OK")
- **`/readiness`**: Basic readiness probe (returns "OK")
- **`/metrics`**: Prometheus metrics endpoint (port 3010)

### Request Processing Configuration
- **Request Limit**: Default `REQUEST_LIMIT=25` concurrent requests
- **Large Request Limit**: `LARGE_REQUEST_LIMIT=5` for requests >20MB
- **Large Request Size**: `LARGE_REQUEST_SIZE=20MB` threshold

## Assessment Methodology

The indexer impact assessment is implemented as a set of modular scripts that can be executed independently or as a coordinated suite. This separation of concerns follows our established design principles.

### Core Implementation Scripts

**1. Prometheus API Metrics Collection (Weight: 70%)**
- **Script**: `scripts/prometheus-metrics.sh`
- **Purpose**: Collect comprehensive metrics from OpenShift Prometheus monitoring
- **Features**: Prometheus endpoint discovery, PromQL queries, percentile calculations
- **Outputs**: Request counts, duration metrics, error rates, capacity utilization

**2. Processing Performance Analysis (Weight: 20%)**
- **Script**: `scripts/performance-analysis.sh` 
- **Purpose**: Analyze request processing efficiency and trends
- **Features**: Success rate calculation, throughput analysis, error breakdown
- **Outputs**: Performance trends, efficiency metrics, bottleneck identification

**3. Capacity Utilization Analysis (Weight: 10%)**
- **Script**: `scripts/capacity-analysis.sh`
- **Purpose**: Monitor capacity limits and resource health
- **Features**: Queue analysis, resource monitoring, health checks
- **Outputs**: Capacity metrics, pod status, trend analysis

**4. PostgreSQL Database Diagnostics**
- **Script**: `scripts/database-diagnostics.sh`
- **Purpose**: Comprehensive database health and performance analysis
- **Features**: Resource statistics, edge analysis, query performance testing
- **Outputs**: Database metrics, relationship statistics, query execution plans

### Orchestration and Execution

**Main Assessment Script**
- **Script**: `scripts/generate-assessment.sh`
- **Purpose**: Coordinate all assessment components and generate final report
- **Features**: Script orchestration, metrics aggregation, JSON report generation
- **Outputs**: Structured assessment report in standardized JSON format

### Usage

**Execute Full Assessment:**
```bash
cd .claude/skills/search-indexer-impact
./scripts/generate-assessment.sh
```

**Execute Individual Components:**
```bash
# Prometheus metrics only
./scripts/prometheus-metrics.sh

# Database diagnostics only
./scripts/database-diagnostics.sh

# Performance analysis only
./scripts/performance-analysis.sh
```

### Performance Thresholds

**Request Processing Rate Levels (per cluster):**
- **Normal**: Steady request rate with <5% variance per cluster
- **Warning**: 5-15% variance in request rate, possible load balancing issues
- **Critical**: >15% variance or request rate drops, indicating cluster connectivity problems

**Request Duration Levels:**
- **Normal**: <2 seconds average processing time (within histogram buckets)
- **Warning**: 2-5 seconds average processing time
- **Critical**: >5 seconds average processing time or timeouts

**Error Rate Levels:**
- **Normal**: <2% error rate (non-200 HTTP responses)
- **Warning**: 2-5% error rate
- **Critical**: >5% error rate

**Capacity Utilization Levels:**
- **Normal**: <80% of request limit (typically <20 concurrent requests)
- **Warning**: 80-95% of request limit (20-24 concurrent requests)
- **Critical**: >95% of request limit (>24 concurrent requests, approaching 25 limit)

**Request Size Distribution:**
- **Normal**: Majority of requests <10,000 changes
- **Warning**: Increasing trend toward large requests (>25,000 changes)
- **Critical**: Frequent requests >100,000 changes overwhelming processing capacity

### Confidence Scoring Algorithm

```python
# Weighted confidence calculation based on actual available metrics
def calculate_indexer_confidence(avg_request_duration, error_rate_percent, capacity_utilization_percent, request_size_trend, metrics_availability):
    # Calculate risk scores: normalize metrics to 0.0-1.0 scale where 1.0 = critical risk
    
    # Request duration: >5 seconds = critical risk
    duration_risk = min(avg_request_duration / 5.0, 1.0)
    
    # Error rate: >5% = critical risk
    error_risk = min(error_rate_percent / 5.0, 1.0)
    
    # Capacity utilization: >95% = critical risk (approaching REQUEST_LIMIT=25)
    capacity_risk = min(capacity_utilization_percent / 95.0, 1.0)
    
    # Request size trend: 1.0 = large requests dominating (critical risk), 0.0 = normal distribution
    size_risk = request_size_trend  # Should be 0.0-1.0 
    
    # Metrics availability: 0.0 = healthy, 1.0 = critical risk
    metrics_risk = 1.0 - metrics_availability  # metrics_availability should be 0.0-1.0 (1.0 = healthy)
    
    # Apply weights to calculate overall risk score: duration (30%), errors (25%), capacity (20%), request size (15%), metrics (10%)
    risk_score = (duration_risk * 0.3) + (error_risk * 0.25) + (capacity_risk * 0.2) + (size_risk * 0.15) + (metrics_risk * 0.1)
    
    # Convert risk score to confidence score (invert so high confidence = good health)
    confidence_score = 1.0 - risk_score
    
    return confidence_score

# Confidence levels (higher = better health)
# 0.9-1.0: EXCELLENT (optimal operation) 
# 0.7-0.9: GOOD (normal operation)
# 0.4-0.7: MEDIUM (monitoring required)
# 0.2-0.4: LOW (intervention needed)
# 0.0-0.2: CRITICAL (immediate action required)
```

## Output Format

**Save assessment results to:** `monitoring_data/impacts/{hub_cluster_id}_indexer_impact.json`

**Hub cluster identification:**
```bash
# Get hub cluster ID from ManagedCluster CR
HUB_CLUSTER_ID=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.clusterID}')
HUB_OCP_VERSION=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.openshiftVersion-major-minor}')
```

**JSON Schema Template:** `templates/assessment-output.json`

The assessment generates a comprehensive JSON report with the following key sections:
- **Assessment metadata**: Type, scope, hub cluster information
- **Confidence scoring**: Overall health assessment and contributing factors
- **Raw metrics**: Detailed performance and capacity metrics
- **Recommendations**: Specific actions based on assessment findings
- **Architectural analysis**: Impact pattern analysis and bottleneck identification

## Architectural Context

### Indexer Impact Chain
```
Cluster Event → Resource Discovery → Resync Trigger → Database Load → Memory Growth → Processing Delays
```

### Common Impact Patterns  
- **Large clusters**: High resource counts stress relationship computation
- **Dynamic workloads**: Frequent resource changes trigger excessive resyncs
- **Network partitions**: Connection failures cause resync storms on recovery
- **Database constraints**: Connection limits become bottleneck under load

### Integration Points
- **With search-collector-impact**: Collector stress feeds into indexer load
- **With search-api-impact**: Indexer delays affect query result freshness  
- **With PostgreSQL monitoring**: Database metrics provide deeper insight

## Tools Available
- **Bash**: Execute kubectl and psql commands for metrics collection
- **Write**: Save assessment results and detailed analysis
- **Read**: Access previous assessments and configuration data

## Critical Success Factors
- **Comprehensive PostgreSQL analysis**: Database pressure, query performance, and data distribution patterns
- **Real-time metrics correlation**: Combine Prometheus metrics with deep database diagnostics
- **Capacity trend monitoring**: Track resource growth, relationship complexity, and processing efficiency
- **Performance bottleneck identification**: Find database query, batch processing, or relationship computation constraints
- **Cross-component impact assessment**: Connect indexer performance to collector sync success and API response times

## Reference Tools

### **ACM Search PostgreSQL Debug Script**
**Source**: `https://github.com/stolostron/search-v2-operator/blob/main/tools/postgres-debug.sh`

The database diagnostics script incorporates query patterns from the official ACM search PostgreSQL debug script, which provides comprehensive database analysis for production troubleshooting. The script can be executed directly for detailed diagnostics:

```bash
# Direct execution of the official debug script
oc exec -it $(oc get pods -l app=postgres -o name | head -1) -n open-cluster-management -- /bin/bash < postgres-debug.sh
```

The diagnostic queries in this skill are adapted from this production tool to provide programmatic assessment capabilities for automated impact analysis.

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