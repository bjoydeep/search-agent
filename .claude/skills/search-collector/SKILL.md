---
name: search-collector
description: ACM Search collector architecture, networking, performance, and cross-cluster troubleshooting
---

# Search Collector Deep Dive

## Source Code Repository
**GitHub**: https://github.com/stolostron/search-collector

### Key Source Files & Patterns
- **Main collector logic**: `pkg/collector/` - Core resource watching and processing
- **Graph relationships**: `pkg/transforms/` - Resource relationship computation
- **Network sync**: `pkg/send/` - HTTP sync to hub indexer
- **Configuration**: `cmd/collector/` - Startup and configuration management
- **Deployment manifests**: `deploy/` - Kubernetes manifests for addon deployment

### Code Exploration Tips
- Start with `cmd/collector/main.go` for initialization flow
- Review `pkg/collector/controller.go` for main processing loop
- Check `pkg/transforms/` for relationship computation logic
- Look at `pkg/send/sender.go` for hub communication patterns

## Current Collector Fleet Status
- Active collectors: !`find_resources --kind=ManagedCluster --outputMode=count --groupBy=status`
- Recent collector issues: !`find_resources --kind=ManagedCluster --status=NotReady,Unknown --ageNewerThan=2h`
- Resource sync activity: !`find_resources --ageNewerThan=1h --outputMode=count --groupBy=cluster --limit=10`
- Fleet resource distribution: !`find_resources --outputMode=summary`

## Core Architecture

### Channel-Based Processing Pipeline
```
K8s Watch APIs → transformChannel → transformer workers → reconciler.Input → sender → HTTP/TLS → Indexer
      ↓              ↓                    ↓                    ↓           ↓
  Dynamic Resource   Go Channels      runtime.NumCPU()    Batch Queue   Exponential
   Discovery       (Async Buffer)    Worker Goroutines   Processing     Backoff
```

### Technical Implementation
- **Dynamic Resource Discovery**: Uses `GenericInformer` rather than static configuration
- **Concurrency Model**: `runtime.NumCPU()` transformer goroutines for efficient processing
- **Memory Optimization**: `GOGC=25` for aggressive garbage collection in resource-constrained environments
- **Graph Data Model**: 5 relationship types: `ownedBy`, `attachedTo`, `runsOn`, `generatedBy`, `mutatedBy`
- **Failure Resilience**: LRU cache prevents out-of-order event corruption during network instability

### Synchronization Patterns
- **Dual State Management**: Complete state + differential state for recovery and efficiency
- **Sync Modes**: Incremental updates (5 operation types) vs Full resync (complete state replacement)
- **Timing**: 5-second report rate, 5-minute heartbeat, 5-minute HTTP timeout
- **Network Handling**: 600-second max exponential backoff with jitter for HTTP transmission

## Common Issues & Solutions

### Resource Discovery Problems
**Symptoms:**
- Missing resources in search results
- Inconsistent resource counts between clusters
- New resource types not appearing

**Diagnostic Commands:**
```bash
# Check collector pod status and resource usage
kubectl get pods -l component=search-collector -o wide
kubectl top pods -l component=search-collector

# Collector logs for resource discovery issues
kubectl logs -l component=search-collector --tail=100 | grep -E "(discovery|informer|watch)"

# Check resource types being watched
kubectl logs -l component=search-collector --tail=500 | grep -E "(GenericInformer|api-resources)"
```

**Common Causes:**
- [TODO: Add specific resource discovery failure patterns you've seen]
- [TODO: Add RBAC issues that prevent resource watching]
- [TODO: Add cluster-specific resource type limitations]

### Network Connectivity Issues
**Symptoms:**
- Collector heartbeat failures
- Sync timeouts to hub indexer
- HTTP/TLS connection errors

**Diagnostic Commands:**
```bash
# Check collector connectivity to hub
kubectl get managedclusteraddons search -A -o custom-columns="CLUSTER:.metadata.namespace,STATUS:.status.conditions[-1].type,REASON:.status.conditions[-1].reason,MESSAGE:.status.conditions[-1].message"

# Network connectivity from collector perspective
kubectl exec -it $(kubectl get pods -l component=search-collector -o name | head -1) -- nslookup search-indexer.open-cluster-management.svc.cluster.local

# Check TLS/HTTP sync errors
kubectl logs -l component=search-collector --tail=100 | grep -E "(HTTP|TLS|timeout|connection)"
```

**Common Causes:**
- [TODO: Add network policy blocking issues]
- [TODO: Add proxy configuration problems]
- [TODO: Add certificate/TLS handshake failures]

### Performance & Scaling Issues
**Symptoms:**
- High CPU/memory usage on managed clusters
- Slow resource processing
- Collector pods being OOMKilled

**Diagnostic Commands:**
```bash
# Resource usage analysis
kubectl top pods -l component=search-collector --sort-by=cpu
kubectl top pods -l component=search-collector --sort-by=memory

# Processing performance metrics
kubectl logs -l component=search-collector --tail=200 | grep -E "(batch|processing|goroutine|GOGC)"

# Check for resource limits and requests
kubectl get pods -l component=search-collector -o jsonpath='{.items[*].spec.containers[*].resources}'
```

**Performance Tuning:**
- Worker goroutine scaling (`runtime.NumCPU()`)
- Memory optimization (`GOGC=25`)
- Channel buffer sizing for async processing
- [TODO: Add resource limit recommendations based on cluster size]
- [TODO: Add performance tuning based on resource types/volume]

### Heartbeat & Health Monitoring
**Symptoms:**
- Collector showing as unhealthy in addon status
- Intermittent connectivity reports
- Stale heartbeat timestamps

**Diagnostic Commands:**
```bash
# Collector health and heartbeat status
kubectl get managedclusteraddons search -A -o yaml | grep -A10 -B5 "heartbeat\|health"

# Recent collector events and errors
kubectl get events --field-selector involvedObject.kind=ManagedClusterAddOn --sort-by=.lastTimestamp | tail -20

# Addon framework health
kubectl get klusterletaddonconfigs -A | grep search
```

**Common Patterns:**
- [TODO: Add heartbeat failure patterns]
- [TODO: Add addon framework issues]
- [TODO: Add lease management problems]

## Live Fleet Diagnostics

### Cross-Cluster Health Overview
```bash
# Get all collector pod status across clusters
# [TODO: Add multi-cluster kubectl commands for fleet-wide status]

# Compare resource sync rates across clusters
# [TODO: Add commands to compare cluster sync performance]

# Identify problematic clusters
# [TODO: Add pattern matching for common cluster issues]
```

### Performance Analysis
```bash
# Resource processing rates by cluster
kubectl logs -l component=search-collector --tail=500 | grep -E "processed.*resources" | sort

# Network latency to hub indexer
kubectl exec -it $(kubectl get pods -l component=search-collector -o name | head -1) -- curl -w "@{time_total: %{time_total}}\n" -o /dev/null -s http://search-indexer:3010/healthz
```

### Graph Relationship Analysis
```bash
# Check relationship computation logs
kubectl logs -l component=search-collector --tail=200 | grep -E "(ownedBy|attachedTo|runsOn|generatedBy|mutatedBy)"

# Validate relationship consistency
# [TODO: Add commands to verify relationship graph integrity]
```

## Cross-Component Routing

### **Network/sync issues affecting indexer** → `/search-indexer`
- HTTP sync timeouts, connection pooling problems
- Batch processing failures at indexer level
- PostgreSQL write performance impact

### **Addon deployment/lifecycle problems** → `/search-operator`
- ManagedClusterAddOn configuration issues
- Addon framework integration problems
- Collector pod deployment failures

### **Resource discovery affecting API queries** → `/search-api`
- Missing resources causing query inconsistencies
- Relationship data gaps affecting GraphQL traversal
- RBAC issues with cross-cluster resource visibility

### **Performance impact on platform** → `/search-performance`
- Collector resource usage affecting cluster performance
- Network overhead impacting other workloads
- Scaling decisions based on collector metrics

## Troubleshooting Decision Tree

```
Collector Issue?
├─ Resource Discovery Problem?
│  ├─ Check pod status + RBAC + logs
│  └─ Verify GenericInformer configuration
├─ Network Connectivity?
│  ├─ Check addon status + TLS logs
│  └─ Test hub connectivity + proxy config
├─ Performance Issue?
│  ├─ Check resource usage + limits
│  └─ Analyze processing rates + GOGC
└─ Health/Heartbeat?
   ├─ Check addon framework status
   └─ Verify lease management + events
```

## Advanced Configuration

### Deployment Modes
- **Hub deployment**: Direct TLS connection to indexer
- **Managed cluster deployment**: Proxy via kubeconfig through addon framework
- **Lease-based health monitoring**: Kubernetes-native heartbeat via addon status

### Failure Handling Patterns
- **Exponential backoff**: 600s max with jitter for HTTP retries
- **Context cancellation**: Graceful shutdown via `getMainContext()` propagation
- **Dual-signal shutdown**: First signal graceful, second signal forced exit
- **Out-of-order protection**: LRU cache prevents event corruption

---

## TODO: Questions for Enhancement

Please help enhance this skill by answering:

### **1. Most Common Collector Issues?**
- What are your top 3-5 collector problems you deal with regularly?
- Network problems? Resource discovery? Performance? Heartbeat failures?
- Any patterns by cluster type, version, or cloud provider?

### **2. Troubleshooting Workflows?**
- What kubectl commands do you run first when collector issues are reported?
- What logs do you check and what patterns do you look for?
- How do you isolate network vs resource discovery vs performance issues?

### **3. Cross-Cluster Patterns?**
- Do you see consistent issues across certain cluster types?
- Special cases: SNO (Single Node OpenShift), disconnected clusters, specific clouds?
- How do you handle fleet-wide collector updates or configuration changes?

### **4. Performance Characteristics?**
- What resource usage (CPU/memory) is normal vs concerning?
- How do you tune collector performance based on cluster size?
- Resource limit recommendations for different cluster profiles?

### **5. Network & Security Patterns?**
- Common network policy issues blocking collector connectivity?
- Proxy configuration problems in enterprise environments?
- Certificate/TLS issues and resolution patterns?

### **6. Addon Framework Integration?**
- Common addon deployment failures and their causes?
- How do you troubleshoot addon framework issues?
- Lease management and health reporting problems?

Please update this skill with your operational experience and real-world patterns!

---

## Code Analysis & Implementation Details

**[📋 Code Analysis](code-analysis.md)** - Comprehensive source code analysis including:
- File navigation and structure
- Configuration options and environment variables
- Channel architecture and Go concurrency patterns
- Performance parameters and optimization settings
- Error patterns and debugging guidance
- Integration interfaces and API details