---
name: search-collector-impact
description: Assess collector stress, networking, and cross-cluster load when clusters are added to or removed from ACM. Use for ManagedCluster events, collector deployment issues, cross-cluster connection problems, or performance degradation related to search collectors.
---

# Search Collector Impact Assessment

## Purpose
Specialized assessment of search collector performance impact when ACM managed clusters are added, removed, or modified. Focuses on connection stress, resource utilization, and cross-cluster networking performance that affects search data collection.

## When to Use
- **ManagedCluster.ADDED events**: New clusters joining ACM
- **Collector deployment issues**: Collector pods failing or restarting
- **Cross-cluster performance problems**: Slow search data collection
- **Connection pool exhaustion**: Too many clusters overwhelming collectors
- **Network latency issues**: Cross-cluster communication delays

## Available Collector Metrics

The search-collector exposes exactly **2 Prometheus metrics** via `/metrics` endpoint on port `5010`:

### Core Metrics
1. **`search_collector_events_received_count`** (Counter with `resource_kind` label)
   - **Purpose**: Tracks total Kubernetes events received by informers
   - **Labels**: `resource_kind` (e.g., "Pod", "Service", "Deployment")
   - **Usage**: Monitor event ingestion rate and volume per resource type

2. **`search_collector_resources_sent_to_indexer_count`** (Counter with `resource_kind` label)  
   - **Purpose**: Tracks resources sent to search-indexer after reconciliation
   - **Labels**: `resource_kind` (e.g., "Pod", "Service", "Deployment")
   - **Usage**: Monitor actual output to indexer after deduplication and processing

### Additional Health Endpoints
- **`/liveness`**: Basic liveness probe (returns "OK")
- **`/readiness`**: Basic readiness probe (returns "OK")  
- **`/metrics`**: Prometheus metrics endpoint (port 5010)

### Derived Monitoring Insights
- **Processing Efficiency**: `resources_sent / events_received` ratio per resource type
- **Event Volume Trends**: Rate of change in `events_received_count`
- **Indexer Throughput**: Rate of change in `resources_sent_to_indexer_count`
- **Resource Type Analysis**: Which Kubernetes resource types generate most events

## Assessment Methodology

### Core Metrics Collection

**1. Actual Collector Prometheus Metrics (Weight: 40%)**
```bash
# Collector Prometheus metrics (available on port 5010/metrics)
# Try multiple label selectors as fallback for collector pods
COLLECTOR_PODS=$(kubectl get pods -l app=search-collector -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
                kubectl get pods -l component=search-collector -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
                kubectl get pods -A | grep search-collector | awk '{print $1"\t"$2}')

echo "$COLLECTOR_PODS" | while read ns pod; do
  echo "=== $ns/$pod Metrics ==="
  
  # Events received by resource type
  echo "Events Received:"
  kubectl exec -n $ns $pod -- curl -s localhost:5010/metrics | grep "search_collector_events_received_count" | grep -v "# HELP\|# TYPE"
  
  # Resources sent to indexer by resource type  
  echo "Resources Sent to Indexer:"
  kubectl exec -n $ns $pod -- curl -s localhost:5010/metrics | grep "search_collector_resources_sent_to_indexer_count" | grep -v "# HELP\|# TYPE"
  
  echo ""
done
```

**2. Cross-Cluster Network Performance Assessment (Weight: 25%)**
```bash
# Analyze collector network performance and connectivity patterns
echo "Cross-cluster network performance analysis:"

# Test hub connectivity from collector perspective
# Try multiple label selectors as fallback for collector pods
COLLECTOR_PODS=$(kubectl get pods -l app=search-collector -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
                kubectl get pods -l component=search-collector -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
                kubectl get pods -A | grep search-collector | awk '{print $1"\t"$2}')

echo "$COLLECTOR_PODS" | while read ns pod; do
  echo "=== $ns/$pod Hub Connectivity ==="
  
  # Test basic connectivity to indexer
  if kubectl exec -n $ns $pod -- timeout 5 nc -zv search-indexer 3010 2>/dev/null; then
    echo "Indexer connectivity: PASS"
  else
    echo "Indexer connectivity: FAIL"
  fi
  
  # Check TLS certificate status
  kubectl exec -n $ns $pod -- curl -s --connect-timeout 3 -k https://search-indexer:3010/liveness >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "TLS handshake: PASS"
  else
    echo "TLS handshake: FAIL"  
  fi
  
  # Analyze recent log patterns for network issues
  kubectl logs -n $ns $pod --tail=50 | grep -E "(timeout|connection|network|TLS|HTTP)" | tail -3 | sed 's/^/  LOG: /'
  
  echo ""
done
```

**3. Processing Efficiency Analysis (Weight: 20%)**
```bash
# Calculate processing efficiency ratios per resource type
# Try multiple label selectors as fallback for collector pods
COLLECTOR_PODS=$(kubectl get pods -l app=search-collector -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
                kubectl get pods -l component=search-collector -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
                kubectl get pods -A | grep search-collector | awk '{print $1"\t"$2}')

echo "$COLLECTOR_PODS" | while read ns pod; do
  echo "=== $ns/$pod Processing Efficiency ==="
  
  # Get all metrics and calculate ratios
  kubectl exec -n $ns $pod -- curl -s localhost:5010/metrics | \
  python3 -c "
import sys
import re

events_received = {}
resources_sent = {}

for line in sys.stdin:
    if 'search_collector_events_received_count' in line and 'resource_kind=' in line:
        match = re.search(r'resource_kind=\"([^\"]+)\".*?(\d+)', line)
        if match:
            events_received[match.group(1)] = int(match.group(2))
    elif 'search_collector_resources_sent_to_indexer_count' in line and 'resource_kind=' in line:
        match = re.search(r'resource_kind=\"([^\"]+)\".*?(\d+)', line)
        if match:
            resources_sent[match.group(1)] = int(match.group(2))

# Calculate efficiency ratios
for resource_kind in events_received.keys():
    received = events_received.get(resource_kind, 0)
    sent = resources_sent.get(resource_kind, 0)
    if received > 0:
        efficiency = (sent / received) * 100
        print(f'{resource_kind}: {received} events → {sent} sent ({efficiency:.1f}% efficiency)')
    else:
        print(f'{resource_kind}: No events received')
"
  echo ""
done
```

**4. Collector Resource Utilization and Health (Weight: 15%)**  
```bash
# Collector pod resource consumption and health analysis
echo "Collector resource usage analysis:"

# Current resource utilization
kubectl top pods -l app=search-collector -A --no-headers | awk '{print $1"/"$2":", "CPU:", $3, "Memory:", $4}'

# Health endpoint validation
# Try multiple label selectors as fallback for collector pods
COLLECTOR_PODS=$(kubectl get pods -l app=search-collector -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
                kubectl get pods -l component=search-collector -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || \
                kubectl get pods -A | grep search-collector | awk '{print $1"\t"$2}')

echo "$COLLECTOR_PODS" | while read ns pod; do
  echo "=== $ns/$pod Health Status ==="
  
  # Test health endpoints with timing
  LIVENESS_TIME=$(kubectl exec -n $ns $pod -- timeout 3 curl -w '%{time_total}' -s localhost:5010/liveness 2>/dev/null | tail -1)
  READINESS_TIME=$(kubectl exec -n $ns $pod -- timeout 3 curl -w '%{time_total}' -s localhost:5010/readiness 2>/dev/null | tail -1)
  
  echo "Liveness response time: ${LIVENESS_TIME}s"
  echo "Readiness response time: ${READINESS_TIME}s"
  
  # Check for recent restart or crash patterns
  RESTART_COUNT=$(kubectl get pod -n $ns $pod -o jsonpath='{.status.containerStatuses[0].restartCount}')
  echo "Restart count: $RESTART_COUNT"
  
  # Look for memory or performance issues in logs
  kubectl logs -n $ns $pod --tail=30 | grep -E "(memory|heap|gc|slow|timeout)" | wc -l | awk '{print "Performance warnings:", $1}'
  
  echo ""
done
```

### Performance Thresholds

**Processing Efficiency Levels:**
- **Normal**: >80% efficiency (events received → resources sent ratio)
- **Warning**: 50-80% efficiency (moderate processing overhead or filtering)  
- **Critical**: <50% efficiency (high event volume with low output, possible backlog)

**Cross-Cluster Network Levels:**
- **Normal**: Hub connectivity stable, TLS handshake success, <1s response times
- **Warning**: Intermittent connectivity issues, slow TLS handshakes (1-3s), occasional timeouts
- **Critical**: Persistent connection failures, TLS handshake failures, frequent timeout errors in logs

**Collector Health Levels:**
- **Normal**: Health endpoints responding <0.5s, restart count stable, minimal performance warnings
- **Warning**: Health endpoints slow (0.5-2s), occasional restarts, some performance warnings in logs
- **Critical**: Health endpoints failing/timeout, frequent restarts, many performance warnings

**Resource Utilization Levels:**
- **Normal**: <80% CPU and memory usage
- **Warning**: 80-90% resource usage
- **Critical**: >90% resource usage

### Confidence Scoring Algorithm

```python
# Weighted confidence calculation based on comprehensive collector assessment
def calculate_collector_confidence(processing_efficiency_avg, network_health_score, collector_health_score, resource_usage_percent):
    # Calculate risk scores: normalize each metric to 0.0-1.0 scale where 1.0 = critical risk
    
    # Processing efficiency: lower efficiency = higher risk (worse)
    efficiency_risk = max(0.0, (80.0 - processing_efficiency_avg) / 80.0)  # 0% efficiency = 1.0 risk
    
    # Network health: connection failures, TLS issues, timeouts (0.0 = healthy, 1.0 = critical risk)
    # network_health_score should be pre-calculated based on connectivity tests and log analysis
    network_risk = network_health_score
    
    # Collector health: restart count, health endpoint performance, log warnings (0.0 = healthy, 1.0 = critical risk)  
    # collector_health_score should be pre-calculated based on health checks and stability metrics
    health_risk = collector_health_score
    
    # Resource usage: higher usage = higher risk (worse)
    resource_risk = min(resource_usage_percent / 90.0, 1.0)  # 90% = critical threshold
    
    # Apply weights to calculate overall risk score: processing efficiency (40%), network health (25%), collector health (20%), resources (15%)
    risk_score = (efficiency_risk * 0.4) + (network_risk * 0.25) + (health_risk * 0.2) + (resource_risk * 0.15)
    
    # Convert risk score to confidence score (invert so high confidence = good health)
    confidence_score = 1.0 - risk_score
    
    return confidence_score

# Confidence levels (higher = better health)
# 0.9-1.0: EXCELLENT (optimal operation)
# 0.7-0.9: GOOD (normal operation)
# 0.4-0.7: MEDIUM (monitoring required)  
# 0.2-0.4: LOW (intervention needed)
# 0.0-0.2: CRITICAL (immediate action required)

# Network health scoring helper
def calculate_network_health_score(connectivity_failures, tls_failures, response_time_avg, timeout_count):
    # Connectivity: >2 failures = critical
    connectivity_score = min(connectivity_failures / 2.0, 1.0)
    
    # TLS: >1 failure = critical
    tls_score = min(tls_failures / 1.0, 1.0)
    
    # Response time: >3s = critical
    response_score = min(response_time_avg / 3.0, 1.0)
    
    # Timeouts: >5 = critical
    timeout_score = min(timeout_count / 5.0, 1.0)
    
    # Equal weighting for network components
    return (connectivity_score + tls_score + response_score + timeout_score) / 4.0

# Collector health scoring helper
def calculate_collector_health_score(restart_count, health_response_time_avg, performance_warning_count):
    # Restarts: >3 = critical
    restart_score = min(restart_count / 3.0, 1.0)
    
    # Health response time: >2s = critical
    health_response_score = min(health_response_time_avg / 2.0, 1.0)
    
    # Performance warnings: >10 = critical
    warning_score = min(performance_warning_count / 10.0, 1.0)
    
    # Equal weighting for health components
    return (restart_score + health_response_score + warning_score) / 3.0
```

## Output Format

**Save assessment results to:** `monitoring_data/impacts/{cluster_name}_collector_impact.json`

```json
{
  "assessment_type": "search-collector-impact",
  "cluster_name": "k3s-rancher",
  "assessment_timestamp": "2026-03-31T16:30:00Z",
  "confidence_score": 0.75,
  "confidence_level": "HIGH",
  "contributing_factors": [
    "Processing efficiency: 45% average (below 50% threshold)",
    "Network health issues: 3 connectivity failures, TLS handshake delays",
    "Collector health degraded: 2 recent restarts, slow health responses", 
    "Resource usage: CPU 85%, Memory 78%"
  ],
  "raw_metrics": {
    "processing_efficiency_avg": 45.0,
    "network_health_score": 0.6,
    "collector_health_score": 0.4,
    "cpu_usage_percent": 85.0,
    "memory_usage_percent": 78.0,
    "active_collectors": 3,
    "collector_metrics": {
      "events_received_total": 15420,
      "resources_sent_total": 6939,
      "efficiency_by_resource": {
        "Pod": {"events": 8500, "sent": 4200, "efficiency": 49.4},
        "Service": {"events": 3200, "sent": 1600, "efficiency": 50.0},
        "Deployment": {"events": 2100, "sent": 900, "efficiency": 42.9},
        "ConfigMap": {"events": 1620, "sent": 239, "efficiency": 14.8}
      }
    },
    "network_analysis": {
      "connectivity_failures": 3,
      "tls_failures": 1,
      "avg_response_time_seconds": 2.8,
      "timeout_count": 2
    },
    "health_analysis": {
      "restart_count": 2,
      "health_response_time_avg": 1.5,
      "performance_warning_count": 8,
      "liveness_status": "PASS",
      "readiness_status": "SLOW"
    }
  },
  "recommendations": [
    "Investigate ConfigMap processing efficiency (14.8%)",
    "Address network connectivity issues affecting hub communication",
    "Investigate recent collector restarts and health response delays",
    "Consider horizontal scaling due to high resource usage",
    "Review TLS certificate status and renewal processes"
  ],
  "architectural_analysis": "k3s-rancher → high Pod event volume → collector processing bottleneck → indexer starvation pattern"
}
```

## Architectural Context

### Collector Impact Chain
```
New ManagedCluster → Collector Discovery → Connection Establishment → Resource Load → API Pressure → Hub Impact
```

### Common Impact Patterns
- **k3s clusters**: Often generate high connection counts due to resource discovery patterns
- **Large production clusters**: Heavy API object counts stress collector memory  
- **Network-isolated clusters**: Higher latency affects collection efficiency
- **Rapid cluster additions**: Connection pool exhaustion from simultaneous discovery

### Integration Points
- **With search-indexer-impact**: Collector stress affects indexing load
- **With search-api-impact**: API overload cascades to query performance
- **With search-architecture**: Understanding cross-cluster topology helps interpret results

## Tools Available
- **Bash**: Execute kubectl commands for metrics collection
- **Write**: Save assessment results and analysis
- **Read**: Access cluster configuration and previous assessments

## Critical Success Factors
- **Real-time assessment**: Collect metrics during active cluster addition events
- **Cross-cluster perspective**: Consider impact across the entire collector fleet
- **Proactive scaling**: Identify connection limits before critical failures
- **Network-aware**: Account for cross-cluster latency in assessments
- **Load correlation**: Connect collector stress to downstream indexer and API impact