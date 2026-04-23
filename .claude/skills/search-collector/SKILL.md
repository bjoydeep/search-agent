---
name: search-collector
description: ACM Search collector architecture, networking patterns, cross-cluster optimization, and channel-based processing strategies
---

# Search Collector Deep Dive

## Purpose
The ACM Search Collector serves as the distributed data collection engine for multi-cluster search capabilities. It runs on managed clusters to discover, process, and transmit resource information to the search indexer on the hub cluster.

## Role in ACM Search Architecture

### Core Responsibilities
- **Dynamic Resource Discovery**: Uses GenericInformer patterns to discover all Kubernetes resources without static configuration
- **Relationship Computation**: Analyzes resource ownership, attachments, and deployment relationships across cluster resources
- **Cross-Cluster Communication**: Manages secure HTTP/TLS transmission to hub cluster search indexer
- **Event Processing**: Transforms Kubernetes watch events into search-optimized resource representations
- **Fleet Integration**: Operates as a distributed component across all managed clusters in the ACM fleet

### Data Flow Position
```
K8s APIs (managed cluster) → Collector → Network → Indexer (hub) → Database → API
```

The collector is the distributed entry point in this flow - its performance directly impacts:
- **Data freshness**: How quickly cluster changes appear in search results
- **Fleet capacity**: How many clusters the search system can handle
- **Network efficiency**: Cross-cluster bandwidth and connection usage
- **Hub load**: Processing pressure on centralized indexer and database

## Optimization Focus
This skill covers collector architecture, channel-based processing patterns, cross-cluster networking optimization, and scaling strategies for multi-cluster environments. Focuses on architectural principles and optimization patterns independent of specific implementation details.

## Core Architecture

### Channel-Based Processing Pipeline
```
K8s Watch APIs → transformChannel → transformer workers → reconciler.Input → sender → HTTP/TLS → Indexer
     ↓              ↓                    ↓                    ↓           ↓
 Dynamic Resource   Go Channels      runtime.NumCPU()    Batch Queue   Exponential
  Discovery       (Async Buffer)    Worker Goroutines   Processing     Backoff
```

### Key Optimization Principles
- **CPU-Scaled Concurrency**: Worker goroutines scale with `runtime.NumCPU()` for efficient resource utilization
- **Memory-Aggressive GC**: `GOGC=25` setting for resource-constrained managed cluster environments
- **Asynchronous Processing**: Channel-based pipeline prevents blocking between discovery, transformation, and transmission
- **Differential State Tracking**: Complete vs incremental state management for network efficiency
- **Failure Resilience**: LRU cache and out-of-order event protection during network instability

### Performance Patterns
- **Paginated Discovery**: 250-resource chunks prevent memory spikes during initial cluster scanning
- **Dynamic Resource Coverage**: GenericInformer approach supports new CRDs without collector updates
- **Relationship Graph Building**: 5 edge types (`ownedBy`, `attachedTo`, `runsOn`, `generatedBy`, `mutatedBy`) for comprehensive topology
- **Connection Management**: TLS 1.2+ with proper certificate handling for cross-cluster security

## Optimization Strategies

### Processing Pipeline Optimization
**Common Problems:**
- High CPU usage during large cluster discovery
- Memory pressure from resource accumulation
- Processing delays affecting data freshness

**Optimization Patterns:**
- **Worker Thread Scaling**: Match goroutine count to CPU cores for optimal concurrency
- **Channel Buffer Sizing**: Right-size async buffers to prevent blocking without excessive memory
- **Memory Management**: Aggressive garbage collection tuning for memory-constrained environments
- **Batch Processing**: Group operations to minimize overhead while maintaining responsiveness

### Cross-Cluster Networking Optimization
**Common Problems:**
- High network overhead from frequent transmissions
- Connection failures affecting data reliability
- TLS handshake overhead for secure communication

**Optimization Patterns:**
- **Differential Transmission**: Send only changes after initial complete sync to minimize bandwidth
- **Exponential Backoff**: Graceful handling of network instability with jitter to prevent storms
- **Connection Reuse**: Maintain persistent connections while handling certificate rotation
- **Payload Optimization**: Efficient JSON serialization with minimal overhead

### Resource Discovery Optimization
**Common Problems:**
- Slow initial cluster scanning affecting time-to-visibility
- Missing new resource types without collector updates
- RBAC limitations preventing complete cluster visibility

**Optimization Patterns:**
- **Informer Pattern**: Use watch streams rather than polling for efficient change detection
- **Dynamic Type Discovery**: GenericInformer supports CRDs without static configuration
- **Cache Management**: UID-based versioning for efficient state reconciliation
- **Permission Design**: Minimal RBAC requirements while maintaining complete visibility

### Memory and Resource Optimization
**Common Problems:**
- Collector pods being OOMKilled on resource-constrained clusters
- High memory usage affecting other cluster workloads
- CPU spikes during processing intensive operations

**Optimization Patterns:**
- **Garbage Collection Tuning**: Aggressive GOGC settings for memory-constrained environments
- **Resource Limit Planning**: Right-size container limits based on cluster scale and complexity
- **Processing Rate Control**: Balance event processing speed with resource consumption
- **Cache Size Management**: LRU cache sizing to prevent unbounded memory growth

## Integration Considerations

### **Impact on Indexer Performance**
- Processing efficiency directly affects indexer request patterns
- Network transmission patterns determine indexer batch processing load
- Connection management affects indexer connection pool utilization

### **Managed Cluster Dependencies**
- Kubernetes API server load increases with collector discovery patterns
- RBAC configuration determines scope of resource visibility
- Network policies and proxy configuration affect hub connectivity

### **Cross-Cluster Networking Requirements**
- TLS certificate management for secure communication
- Network routing and firewall configuration for hub access
- Proxy configuration for enterprise environments

### **Fleet Scaling Characteristics**
- Linear increase in network traffic with cluster count
- Connection management becomes critical at scale
- Certificate rotation coordination across distributed fleet

## Scaling & Optimization Strategies

### Horizontal Scaling Patterns
- **Fleet Distribution**: Design for efficient resource utilization across many managed clusters
- **Processing Load**: Balance discovery intensity with cluster resource constraints
- **Network Coordination**: Prevent simultaneous transmission storms across fleet
- **State Management**: Handle collector restarts and network partitions gracefully

### Performance Tuning Approaches
- **CPU Optimization**: Match worker threads to available cores for optimal processing
- **Memory Optimization**: Tune garbage collection for managed cluster memory constraints
- **Network Efficiency**: Optimize transmission patterns to minimize cross-cluster bandwidth
- **Discovery Rate**: Balance resource freshness with cluster API server impact

### Capacity Planning
- **Cluster Scale Estimation**: Understand relationship between cluster size and collector resource requirements
- **Network Bandwidth Planning**: Account for cross-cluster data transmission patterns
- **Resource Constraint Design**: Plan for resource-limited managed cluster environments
- **Growth Pattern Analysis**: Design for logarithmic scaling as fleet size increases

### Cross-Cluster Architecture Considerations
- **Hub Connectivity**: Design for reliable cross-cluster network communication
- **Certificate Management**: Handle distributed TLS certificate lifecycle
- **Network Partitioning**: Graceful handling of managed cluster isolation scenarios
- **Fleet Coordination**: Prevent synchronized behavior that could overwhelm hub components

---

## Implementation Details

For specific configuration values, file paths, environment variables, and implementation details, see:

**[📋 Code Analysis](code-analysis.md)** - Comprehensive technical implementation guide including:
- Source file navigation and package organization
- Configuration options and environment variables  
- Channel architecture and Go concurrency patterns
- Network implementation and TLS security settings
- Performance parameters and resource optimization
- Error patterns, debugging approaches, and troubleshooting
- Integration interfaces and API details