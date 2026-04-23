---
name: search-operator-impact
description: Assess search operator deployment disruption, resource consumption, and reconciliation performance during operator upgrades, component deployments, or ManagedClusterAddOn changes. Use for operator upgrade events, addon deployment issues, component lifecycle problems, or reconciliation delays.
---

# Search Operator Impact Assessment

## Purpose
Specialized assessment of search operator performance impact during upgrades, component deployments, or ManagedClusterAddOn changes. Focuses on reconciliation performance, resource consumption, component deployment success rates, and addon framework integration health.

## When to Use
- **Operator upgrade events**: Search operator version changes or configuration updates
- **Component deployment disruption**: Indexer, API, or PostgreSQL deployment issues
- **ManagedClusterAddOn problems**: Search collector deployment failures across clusters
- **Reconciliation performance issues**: Search CR processing delays
- **Resource consumption spikes**: Operator using excessive CPU or memory

## Available Operator Metrics

The search operator may expose Prometheus metrics via the standard operator framework. While operator-specific metrics may be limited, we can leverage controller-runtime metrics and OpenShift monitoring infrastructure.

### Controller-Runtime Metrics (Standard)
1. **`controller_runtime_reconcile_total`** (Counter with `controller` and `result` labels)
   - **Purpose**: Total reconciliation attempts by controller and result (success/error/requeue)
   - **Labels**: `controller` (e.g., "search"), `result` ("success", "error", "requeue")
   - **Usage**: Monitor reconciliation success rates and error patterns

2. **`controller_runtime_reconcile_time_seconds`** (Histogram with `controller` label)
   - **Purpose**: Time spent reconciling Search CRs
   - **Labels**: `controller` (e.g., "search")
   - **Usage**: Track reconciliation performance and detect slowdowns

3. **`workqueue_depth`** (Gauge with `name` label)
   - **Purpose**: Current depth of work queue
   - **Labels**: `name` (e.g., "search-controller")
   - **Usage**: Monitor operator workload and potential backlog

4. **`workqueue_adds_total`** (Counter with `name` label)
   - **Purpose**: Total items added to work queue
   - **Labels**: `name` (e.g., "search-controller")
   - **Usage**: Track operator activity and workload patterns

### Additional Component Metrics
- **Search CR conditions**: Via Kubernetes API monitoring
- **Deployment status**: For indexer, API, PostgreSQL components
- **ManagedClusterAddOn deployment**: Cross-cluster addon success rates

## Assessment Methodology

The operator impact assessment is implemented as a set of modular scripts that can be executed independently or as a coordinated suite. This separation of concerns follows our established design principles.

### Core Implementation Scripts

**1. Prometheus Operator Metrics Collection (Weight: 40%)**
- **Script**: `scripts/prometheus-metrics.sh`
- **Purpose**: Collect comprehensive operator metrics from OpenShift Prometheus monitoring
- **Features**: Advanced/fallback query patterns, controller-runtime metrics focus
- **Outputs**: Reconciliation success rates, duration metrics, work queue health, operator activity patterns

**2. Component Deployment Health Analysis (Weight: 25%)**
- **Script**: `scripts/component-deployment.sh`
- **Purpose**: Analyze operator-managed component deployment health and Search CR status
- **Features**: Multi-component health checks, Search CR condition analysis, deployment event tracking
- **Outputs**: Component availability status, deployment success rates, Search CR health assessment

**3. ManagedClusterAddOn Deployment Analysis (Weight: 20%)**
- **Script**: `scripts/addon-deployment.sh`
- **Purpose**: Monitor cross-cluster addon deployment success and ManifestWork health
- **Features**: Fleet-wide addon analysis, ManifestWork tracking, cluster-specific deployment status
- **Outputs**: Addon deployment success rates, failed cluster identification, ManifestWork health metrics

**4. Operator Resource Analysis (Weight: 15%)**
- **Script**: `scripts/resource-analysis.sh`
- **Purpose**: Monitor operator resource consumption, stability, and leader election health
- **Features**: Resource usage tracking, leader election analysis, operator stability indicators
- **Outputs**: Resource consumption metrics, leader election stability, operator restart patterns

### Orchestration and Execution

**Main Assessment Script**
- **Script**: `scripts/generate-assessment.sh`
- **Purpose**: Coordinate all assessment components and generate final report
- **Features**: Script orchestration, metrics aggregation, comprehensive audit logging
- **Outputs**: Structured assessment report with execution audit trail

### Usage

**Execute Full Assessment:**
```bash
cd .claude/skills/search-operator-impact
./scripts/generate-assessment.sh
```

**Execute Individual Components:**
```bash
# Prometheus metrics only
./scripts/prometheus-metrics.sh

# Component deployment health only
./scripts/component-deployment.sh

# Addon deployment analysis only
./scripts/addon-deployment.sh

# Resource analysis only
./scripts/resource-analysis.sh
```

### Performance Thresholds

**Reconciliation Performance Levels:**
- **Normal**: <30 seconds average reconciliation time, >95% success rate
- **Warning**: 30-60 seconds reconciliation time, 90-95% success rate
- **Critical**: >60 seconds reconciliation time, <90% success rate

**Component Deployment Levels:**
- **Normal**: All components available and ready
- **Warning**: 1 component degraded or intermittent restarts
- **Critical**: Multiple components failed or constant restart loops

**Addon Deployment Levels:**
- **Normal**: >95% addon deployment success rate across clusters
- **Warning**: 90-95% addon deployment success rate
- **Critical**: <90% addon deployment success rate

**Resource Consumption Levels:**
- **Normal**: <70% of resource requests/limits
- **Warning**: 70-85% of resource requests/limits
- **Critical**: >85% of resource requests/limits

### Confidence Scoring Algorithm

```python
# Weighted confidence calculation based on operator health metrics
def calculate_operator_confidence(reconciliation_success_rate, deployment_success_rate, addon_success_rate, resource_usage_percent, reconciliation_duration_avg, metrics_availability):
    # Calculate risk scores: normalize metrics to 0.0-1.0 scale where 1.0 = critical risk
    
    # Reconciliation performance: convert success rate to risk score
    reconcile_perf_risk = max(0.0, (100.0 - reconciliation_success_rate) / 100.0)  # 0% success = 1.0 risk
    
    # Component deployment health: convert success rate to risk score  
    deployment_risk = max(0.0, (100.0 - deployment_success_rate) / 100.0)  # 0% success = 1.0 risk
    
    # Addon deployment success: convert success rate to risk score
    addon_risk = max(0.0, (100.0 - addon_success_rate) / 100.0)  # 0% success = 1.0 risk
    
    # Resource usage: >85% = critical risk
    resource_risk = min(resource_usage_percent / 85.0, 1.0)
    
    # Reconciliation duration: >60s = critical risk
    duration_risk = min(reconciliation_duration_avg / 60.0, 1.0)
    
    # Metrics availability: 0.0 = healthy, 1.0 = critical risk  
    metrics_risk = 1.0 - metrics_availability
    
    # Apply weights to calculate overall risk score: reconciliation (30%), deployment (20%), addon (20%), resources (15%), duration (10%), metrics (5%)
    risk_score = (reconcile_perf_risk * 0.3) + (deployment_risk * 0.2) + (addon_risk * 0.2) + (resource_risk * 0.15) + (duration_risk * 0.1) + (metrics_risk * 0.05)
    
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

**Save assessment results to:** `monitoring_data/impacts/{hub_cluster_id}_operator_impact.json`

**Hub cluster identification:**
```bash
# Get hub cluster ID from ManagedCluster CR
HUB_CLUSTER_ID=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.clusterID}')
HUB_OCP_VERSION=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.openshiftVersion-major-minor}')
```

The assessment generates a comprehensive JSON report with the following key sections:
- **Assessment metadata**: Type, scope, hub cluster information
- **Confidence scoring**: Overall health assessment and contributing factors
- **Raw metrics**: Detailed reconciliation, component, addon, and resource metrics
- **Recommendations**: Specific actions based on assessment findings
- **Execution audit trail**: Complete transparency into data collection operations

## Architectural Context

### Operator Impact Chain  
```
Operator Change → Component Reconciliation → Deployment Updates → Addon Distribution → Cross-Cluster Impact
```

### Common Impact Patterns
- **Operator upgrades**: New versions can introduce reconciliation delays
- **Resource constraints**: Large fleets stress operator performance
- **Network issues**: Cross-cluster addon deployments fail during network partitions
- **Configuration drift**: Manual changes interfere with operator reconciliation

### Integration Points
- **With search-collector-impact**: Operator addon deployment affects collector availability
- **With search-indexer-impact**: Component deployment issues affect indexing
- **With ACM server foundation**: Addon framework dependencies

## Tools Available
- **Bash**: Execute kubectl commands for metrics collection and log analysis
- **Write**: Save assessment results and operator health analysis
- **Read**: Access previous assessments and operator configuration

## Critical Success Factors
- **Reconciliation monitoring**: Track Search CR processing performance continuously
- **Cross-cluster awareness**: Monitor addon deployment success across entire fleet
- **Resource scaling**: Ensure operator can handle fleet growth
- **Component stability**: Detect deployment issues before they cascade
- **Upgrade impact assessment**: Understand operator change effects on search functionality

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
- **Multi-source Data Collection**: Prometheus metrics, Kubernetes API, component health, addon deployment status
- **Advanced/Fallback Patterns**: Graceful degradation when advanced queries fail
- **Cross-cluster Analysis**: Fleet-wide addon deployment monitoring
- **Resource Trend Analysis**: Historical and current operator resource consumption
- **Complete Transparency**: Full execution audit trail for debugging and validation