# ACM Search Collector - Comprehensive Code Analysis

## Table of Contents
1. [Source File Navigation](#source-file-navigation)
2. [Configuration Options](#configuration-options)
3. [Channel Architecture](#channel-architecture)
4. [Resource Discovery](#resource-discovery)
5. [Network Implementation](#network-implementation)
6. [Performance Parameters](#performance-parameters)
7. [Error Patterns](#error-patterns)
8. [Integration Interfaces](#integration-interfaces)

---

## Source File Navigation

### Core Entry Point
- **`main.go`** - Application bootstrap, component orchestration, graceful shutdown
  - Initializes logger, config, metrics server
  - Creates informers → transformers → reconciler → sender pipeline
  - CPU-based worker thread scaling
  - Signal handling for graceful termination

### Package Organization

#### **`pkg/config/`** - Configuration Management
- **`config.go`** - Three-tier configuration system (env vars > config file > defaults)
- Environment variables: `AGGREGATOR_URL`, `CLUSTER_NAME`, `REPORT_RATE_MS`, `MAX_BACKOFF_MS`
- Development vs. hub deployment validation logic
- Kubernetes client configuration bootstrapping

#### **`pkg/informer/`** - Resource Discovery & Monitoring
- **`informer.go`** - Generic Kubernetes informer implementation
- Paginated resource listing (250-item chunks)
- Watch stream management with exponential backoff
- UID-based resource version tracking
- Atomic initialization flags for consumer synchronization

#### **`pkg/transforms/`** - Data Processing & Relationships
- **`common.go`** - Shared transformation utilities and edge building patterns
- **`pod.go`**, **`deployment.go`**, etc. - Resource-specific transformers
- **`README.md`** - Data model documentation and relationship definitions
- Property extraction, relationship mapping, JSONPath-based custom properties

#### **`pkg/reconciler/`** - State Management
- **`reconciler.go`** - Event processing and state diff computation
- Three-way state tracking: current, previous, diff
- Producer-consumer pattern with mutex-protected critical sections
- LRU cache for deleted nodes to handle out-of-order events

#### **`pkg/send/`** - Network Communication
- **`sender.go`** - Payload transmission with retry logic
- **`httpsClient.go`** - TLS configuration and HTTP client setup
- Exponential backoff with jitter, differential vs. complete sync strategies
- HTTP 429 handling, connection validation

#### **`pkg/metrics/`** - Observability
- **`metrics.go`** - Prometheus counter metrics
- EventsReceivedCount, ResourcesSentToIndexerCount by resource kind
- Pipeline throughput and bottleneck identification

#### **`pkg/lease/`** - Distributed Coordination
- **`lease.go`** - Cluster heartbeat and health monitoring
- Dual-cluster lease strategy (managed cluster + hub fallback)
- Client resilience via configuration reloading

#### **`pkg/server/`** - HTTP Endpoints
- **`server.go`** - Health checks and metrics exposure
- `/liveness`, `/readiness` endpoints for Kubernetes probes
- Prometheus metrics at `/metrics` endpoint

---

## Configuration Options

### Network & Communication
```bash
# Hub connection settings
AGGREGATOR_URL="https://localhost:3010"           # Default aggregator endpoint
AGGREGATOR_HOST="localhost"                       # Alternative host specification
AGGREGATOR_PORT="3010"                           # Alternative port specification

# Cluster identity
CLUSTER_NAME="local-cluster"                      # Cluster identifier
POD_NAMESPACE="open-cluster-management"           # Pod deployment namespace
```

### Timing Parameters
```bash
# Performance tuning
REPORT_RATE_MS=5000                              # Change reporting interval (5s)
HEARTBEAT_MS=300000                              # Connection keepalive (5min)
MAX_BACKOFF_MS=600000                            # Maximum retry delay (10min)
RETRY_JITTER_MS=5000                             # Backoff randomization (5s)
```

### Data Collection Flags
```bash
# Feature toggles
COLLECT_ANNOTATIONS=true                         # Include annotations ≤64 chars
COLLECT_STATUS_CONDITIONS=true                   # Capture status conditions
COLLECT_CRD_PRINTER_COLUMNS=true                # Additional CRD columns
```

### Deployment Mode
```bash
# Deployment configuration
DEPLOYED_IN_HUB=true                            # Hub vs. managed cluster mode
```

### Configuration File (`config.json`)
```json
{
  "aggregatorURL": "https://localhost:3010",
  "clusterName": "local-cluster",
  "clusterNamespace": "local-cluster-ns",
  "reportRateMS": 5000,
  "runtimeMode": "development",
  "deployedInHub": true
}
```

---

## Channel Architecture

### Producer-Consumer Pipeline
```
Kubernetes Events → Informer Channel → Transform Workers → Reconciler Channel → Sender
```

### Goroutine Patterns

#### **Informer Pattern**
- **Single background goroutine** per resource type
- **Channel**: Informer → Transform Workers
- **Backoff**: Exponential (2s increments, max 2min)
- **Synchronization**: `WaitUntilInitialized()` for consumer coordination

#### **Transform Workers**
- **Worker Count**: `runtime.NumCPU()` threads
- **Pattern**: Fan-out from informer channel to CPU-count workers
- **Processing**: Resource-specific `BuildNode()` and `BuildEdges()` functions

#### **Reconciler Pattern**
```go
// Single background receiver
go r.receive() // Continuous event processing

// Mutex-protected state updates
func (r *Reconciler) reconcileNode() {
    r.lock.Lock()
    defer r.lock.Unlock()
    // State validation and updates
}
```

#### **Sender Pattern**
- **Single goroutine** for network operations
- **Retry Strategy**: Exponential backoff with jitter
- **Payload Types**: Differential vs. complete state transmission

### Channel Buffer Strategies
- **Informer Channels**: Unbuffered (synchronous handoff)
- **Transform Channels**: CPU-count sized buffers
- **Error Channels**: Small buffers (1-2) for exception handling

---

## Resource Discovery

### Kubernetes Informer Implementation

#### **Initial Discovery Process**
```go
// Paginated resource listing
func listAndResync() {
    limit := 250  // Prevent memory spikes
    // List resources in chunks
    // Fire ADDED events for each resource
    // Reconcile with cached state
}
```

#### **Watch Stream Management**
```go
// Event types processed
switch event.Type {
case watch.Added:    // Cache UID, call AddFunc
case watch.Modified: // Update cache, call UpdateFunc
case watch.Deleted:  // Remove from cache, call DeleteFunc
case watch.Error:    // Terminate watch, trigger retry
}
```

#### **Dynamic Resource Discovery**
- **GVR-based**: GroupVersionResource identification
- **Cache Strategy**: UID → ResourceVersion mapping
- **Pagination**: 250-item chunks to manage memory
- **State Reconciliation**: Compare cluster vs. cache state

### Resource Type Coverage
Based on transform package analysis, supports 60+ Kubernetes resource types:
- **Core**: Pod, Service, Node, Namespace, ConfigMap, Secret
- **Workloads**: Deployment, StatefulSet, DaemonSet, Job, CronJob
- **Storage**: PersistentVolume, PersistentVolumeClaim, StorageClass
- **Policy**: NetworkPolicy, PodSecurityPolicy, ValidatingAdmissionPolicy
- **Custom**: All CRDs with automatic property extraction

### Resource Relationship Discovery
```go
// Common edge patterns implemented
edgesByOwner()                    // Kubernetes ownership chains
edgesByKyverno()                  // Policy-generated resources
edgesByGatekeeperMutation()       // Admission controller relationships
edgesByDefaultTransformConfig()   // Custom relationship configurations
```

---

## Network Implementation

### HTTPS Client Configuration

#### **TLS Security Settings**
```go
// Modern TLS configuration
tls.Config{
    MinVersion: tls.VersionTLS12,
    CipherSuites: []uint16{
        tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
    },
    CurvePreferences: []tls.CurveID{
        tls.CurveP521, tls.CurveP384, tls.CurveP256,
    },
}
```

#### **Deployment-Specific Client Paths**
```go
// Klusterlet deployment
client := rest.UnversionedRESTClientFor(config)

// Hub deployment
client := &http.Client{
    Transport: &http.Transport{
        TLSClientConfig: tlsConfig,
    },
}
```

### HTTP Sync Patterns

#### **Payload Structure**
```go
type Payload struct {
    AddResources     []Resource `json:"addResources"`
    UpdatedResources []Resource `json:"updatedResources"`
    DeletedResources []Resource `json:"deletedResources"`
    AddEdges         []Edge     `json:"addEdges"`
    UpdatedEdges     []Edge     `json:"updatedEdges"`
    DeletedEdges     []Edge     `json:"deletedEdges"`
    ClearAll         bool       `json:"clearAll"`
}
```

#### **Transmission Strategies**
1. **First Sync**: Complete payload with `ClearAll: true`
2. **Subsequent Syncs**: Differential updates only
3. **Error Recovery**: Fallback to complete payload, reset `lastSentTime`

### Retry Logic Implementation

#### **Exponential Backoff Calculation**
```go
// Backoff formula
backoffMs := 1000 * math.Exp2(float64(retry))
if backoffMs > MaxBackoffMS {
    backoffMs = MaxBackoffMS
}

// Add jitter to prevent thundering herd
jitter := rand.Intn(RetryJitterMS)
time.Sleep(time.Duration(backoffMs + jitter) * time.Millisecond)
```

#### **Error Classification**
- **HTTP 429**: Retry with same payload (rate limiting)
- **Other errors**: Reload config, send complete payload
- **Success**: Reset backoff counter

### Connection Health Validation
```go
// Status comparison for validation
if payload.TotalResources != status.ResourcesReceived {
    // Connection state mismatch detected
}
```

---

## Performance Parameters

### Build-Time Optimizations

#### **Garbage Collection Tuning**
```bash
# Aggressive GC for memory optimization
GOGC=25 go build

# Explanation: GC triggers at 25% heap growth
# Default is 100% - this reduces memory at CPU cost
```

#### **CGO Configuration**
```bash
# Enable C bindings for performance
CGO_ENABLED=1 go build

# Benefits: Native library integration, performance-critical operations
```

### Runtime Performance Settings

#### **Worker Thread Scaling**
```go
// CPU-based worker allocation
workerCount := runtime.NumCPU()

// Transform workers scale with available cores
for i := 0; i < workerCount; i++ {
    go transformWorker(inputChannel, outputChannel)
}
```

#### **Memory Optimization Parameters**
- **Paginated Listing**: 250-resource chunks prevent memory spikes
- **LRU Cache**: Recently deleted nodes (prevents unbounded growth)
- **Deep Copy Strategy**: Explicit map duplication for state snapshots

### Processing Rate Tuning

#### **Configurable Intervals**
```bash
REPORT_RATE_MS=5000      # How often to send changes (default: 5s)
HEARTBEAT_MS=300000      # Keepalive interval (default: 5min)
```

#### **Backoff Parameters**
```bash
MAX_BACKOFF_MS=600000    # Maximum retry delay (default: 10min)
RETRY_JITTER_MS=5000     # Randomization window (default: 5s)
```

### Prometheus Metrics for Performance Monitoring
```go
// Key performance indicators
EventsReceivedCount        // Resource events from informers
ResourcesSentToIndexerCount // Successful transmissions

// Analysis patterns
Pipeline Efficiency = ResourcesSent / EventsReceived
Resource-Specific Bottlenecks = Compare by kind labels
```

### Performance Debugging Flags
```bash
# Development performance analysis
go run -race ./main.go          # Race condition detection
go test -v -cover               # Coverage analysis with verbose output
./search-collector --v=2        # Verbose logging for debugging
```

---

## Error Patterns

### Common Failure Modes & Code Locations

#### **1. Initial Sync Failures**
**Location**: `pkg/informer/informer.go` - `listAndResync()`
```go
// Symptoms: Informer stuck in retry loop
// Root Causes:
// - RBAC permissions insufficient
// - API server connectivity issues
// - Resource type not supported in cluster

// Debug pattern:
if err := r.lister.List(options); err != nil {
    r.retryCount++
    backoff := time.Second * time.Duration(2*r.retryCount)
    // Log: "Failed to list resources, retrying in Xs"
}
```

#### **2. Transform Worker Panics**
**Location**: `pkg/transforms/common.go` - Transform functions
```go
// Symptoms: Worker goroutines crash
// Root Causes:
// - Nil pointer access on malformed resources
// - JSONPath extraction failures
// - Type assertion failures

// Recovery pattern: Workers restart automatically
// Debug: Check resource structure in test-data/
```

#### **3. Network Transmission Errors**
**Location**: `pkg/send/sender.go` - `Sync()` method
```go
// HTTP 429 - Rate Limited
if resp.StatusCode == http.StatusTooManyRequests {
    // Retry with exponential backoff
    // Keep same payload, don't reset state
}

// Other HTTP errors
// Reload configuration, send complete payload
config.ReloadConfig()
lastSentTime = -1  // Force complete sync
```

#### **4. TLS Certificate Issues**
**Location**: `pkg/send/httpsClient.go` - Certificate loading
```go
// Development fallback - DANGEROUS in production
if cert, err := tls.LoadX509KeyPair(certFile, keyFile); err != nil {
    InsecureSkipVerify = true  // Security risk!
}
```

#### **5. Memory Pressure Patterns**
**Location**: `pkg/reconciler/reconciler.go` - State management
```go
// Symptoms: OOMKilled containers
// Root Causes:
// - Large cluster state accumulation
// - Insufficient GOGC tuning
// - LRU cache unbounded growth

// Mitigation: Monitor RSS memory, tune GOGC
```

### Error Recovery Strategies

#### **Informer Resilience**
```go
// Exponential backoff with cap
backoff := time.Second * time.Duration(2*retryCount)
if backoff > time.Minute*2 {
    backoff = time.Minute * 2
}
```

#### **Client Reloading**
```go
// pkg/lease/lease.go
func reloadClient() {
    // Refresh Kubernetes client on persistent errors
    // Protects against stale configuration
}
```

#### **State Consistency Recovery**
```go
// Force complete resync on validation failure
if expectedCount != actualCount {
    clearAll = true
    lastSentTime = -1
}
```

### Debugging Commands
```bash
# Container logs analysis
kubectl logs deployment/search-collector -n open-cluster-management

# Check informer initialization
curl http://localhost:5010/readiness

# Monitor resource processing rates
curl http://localhost:5010/metrics | grep events_received

# Validate network connectivity to hub
kubectl get secret search-indexer-certs -o yaml
```

---

## Integration Interfaces

### Indexer Communication Protocol

#### **Payload Format**
```json
{
  "addResources": [
    {
      "uid": "cluster1/pod/default/nginx-abc123",
      "kind": "Pod",
      "properties": {
        "name": "nginx",
        "namespace": "default",
        "created": "2024-01-15T10:30:00Z",
        "status": "Running"
      }
    }
  ],
  "addEdges": [
    {
      "sourceUID": "cluster1/pod/default/nginx-abc123",
      "destUID": "cluster1/node/worker-1",
      "edgeType": "runsOn"
    }
  ],
  "clearAll": false
}
```

#### **Status Validation Response**
```json
{
  "resourcesReceived": 1247,
  "edgesReceived": 892,
  "lastReceived": "2024-01-15T10:35:22Z"
}
```

### Addon Framework Integration

#### **Klusterlet Agent Pattern**
```go
// Hub credentials mounted via addon framework
kubeconfig := "/var/run/secrets/hub/kubeconfig"
client := kubernetes.NewForConfigOrDie(config)

// Lease-based heartbeat coordination
lease := coordinationv1.Lease{
    ObjectMeta: metav1.ObjectMeta{
        Name:      clusterName,
        Namespace: clusterName,
    },
    Spec: coordinationv1.LeaseSpec{
        RenewTime: &metav1.MicroTime{Time: time.Now()},
    },
}
```

#### **Managed Cluster Communication**
```go
// Dual-path lease strategy
// 1. Update lease on managed cluster (preferred)
// 2. Fallback to hub-cluster namespace if local fails

if err := managedClient.Update(lease); err != nil {
    // Fallback to hub representation
    hubClient.Update(hubLease)
}
```

### Resource Relationship Interfaces

#### **Ownership Edge Building**
```go
// pkg/transforms/common.go
func edgesByOwner(resource *Resource) []Edge {
    edges := []Edge{}

    // Process Kubernetes owner references
    for _, owner := range resource.OwnerReferences {
        edges = append(edges, Edge{
            SourceUID: resource.UID,
            DestUID:   buildUID(clusterName, owner.Kind, namespace, owner.Name),
            EdgeType:  "ownedBy",
        })
    }

    return edges
}
```

#### **Application Topology Interfaces**
```go
// Hosting subscription annotation pattern
hostingSubscription := resource.Annotations["apps.open-cluster-management.io/hosting-subscription"]
if hostingSubscription != "" {
    // Create deployment edge to subscription
    edge := Edge{
        SourceUID: resource.UID,
        DestUID:   buildSubscriptionUID(hostingSubscription),
        EdgeType:  "deployedBy",
    }
}
```

#### **Storage Attachment Interfaces**
```go
// Pod volume relationship discovery
func buildPodStorageEdges(pod *v1.Pod) []Edge {
    edges := []Edge{}

    // ConfigMap and Secret attachments
    for _, volume := range pod.Spec.Volumes {
        if volume.ConfigMap != nil {
            edges = append(edges, attachedToEdge(pod, "ConfigMap", volume.ConfigMap.Name))
        }
        if volume.Secret != nil {
            edges = append(edges, attachedToEdge(pod, "Secret", volume.Secret.SecretName))
        }
    }

    return edges
}
```

### Metrics Integration Points

#### **Prometheus Metrics Export**
```go
// Standard Prometheus exposition
http.Handle("/metrics", promhttp.HandlerFor(PromRegistry, promhttp.HandlerOpts{}))

// Custom metrics registration
EventsReceivedCount = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "search_collector_events_received_total",
        Help: "Total events received from Kubernetes informers",
    },
    []string{"resource_kind"},
)
```

#### **Health Check Integration**
```go
// Kubernetes probe endpoints
"/liveness"  -> HTTP 200 if collector running
"/readiness" -> HTTP 200 if informers initialized

// Integration with cluster monitoring
kind: Pod
spec:
  containers:
  - name: search-collector
    livenessProbe:
      httpGet:
        path: /liveness
        port: 5010
    readinessProbe:
      httpGet:
        path: /readiness
        port: 5010
```

---

## Performance Tuning Guidance

### Memory Optimization
```bash
# Aggressive garbage collection
export GOGC=25

# Container resource limits
resources:
  limits:
    memory: "512Mi"
  requests:
    memory: "256Mi"
```

### Network Performance
```bash
# Tune reporting intervals for cluster size
REPORT_RATE_MS=10000     # Large clusters: longer intervals
HEARTBEAT_MS=600000      # Reduce heartbeat frequency
```

### Debugging Performance Issues
```bash
# Monitor resource processing rates
watch -n 5 'curl -s localhost:5010/metrics | grep -E "(events_received|resources_sent)"'

# Container resource utilization
kubectl top pod -n open-cluster-management | grep search-collector

# Network latency to hub
kubectl exec deployment/search-collector -n open-cluster-management -- \
  curl -w "@curl-format.txt" -s -o /dev/null $AGGREGATOR_URL/healthz
```

---

## Troubleshooting Quick Reference

### 1. **Collector Not Starting**
```bash
# Check configuration
kubectl get configmap search-collector-config -o yaml

# Verify RBAC permissions
kubectl auth can-i list pods --as=system:serviceaccount:open-cluster-management:search-collector

# Check hub connectivity
kubectl get secret search-indexer-certs -o yaml
```

### 2. **Missing Resources in Search**
```bash
# Verify informer initialization
curl localhost:5010/readiness

# Check resource discovery
curl localhost:5010/metrics | grep events_received_total

# Validate transform functions
kubectl logs deployment/search-collector | grep "transform error"
```

### 3. **High Memory Usage**
```bash
# Tune garbage collection
kubectl patch deployment search-collector --patch '
spec:
  template:
    spec:
      containers:
      - name: search-collector
        env:
        - name: GOGC
          value: "25"'

# Monitor memory trends
kubectl top pod -l app=search-collector --containers
```

### 4. **Network Connectivity Issues**
```bash
# Test aggregator connectivity
kubectl exec deployment/search-collector -- curl -I $AGGREGATOR_URL

# Check certificate expiration
kubectl get secret search-indexer-certs -o yaml | base64 -d | openssl x509 -dates

# Verify TLS configuration
kubectl logs deployment/search-collector | grep -i tls
```

This comprehensive analysis provides practical guidance for developers working with the ACM Search Collector, covering the complete architecture from initialization through error recovery and performance optimization.

### Search Custom Resource Specification

#### Database Configuration
```yaml
apiVersion: search.open-cluster-management.io/v1alpha1
kind: Search
metadata:
  name: search-v2-operator
spec:
  # Storage configuration
  dbStorage:
    size: "10Gi"                  # Default: 10Gi, customizable
    storageClassName: ""          # Optional storage class

  # Database parameters via ConfigMap
  dbConfig:
    name: "custom-db-config"      # ConfigMap reference

  # External database (placeholder - not implemented)
  externalDBInstance:
    secretName: "external-db-secret"
```

#### Component Deployment Customization
```yaml
spec:
  deployments:
    database:
      replicas: 1                 # Minimum: 1, forced to 1 in implementation
      imageOverride: "custom/postgres:16"
      resources:
        requests:
          cpu: "25m"
          memory: "1Gi"
        limits:
          memory: "4Gi"
      env:
        - name: "WORK_MEM"
          value: "4MB"

    indexer:
      replicas: 1
      resources:
        requests:
          cpu: "10m"
          memory: "32Mi"
      arguments: ["--custom-arg"]

    collector:
      replicas: 1                 # Forced to 1 in implementation
      resources:
        requests:
          cpu: "25m"
          memory: "128Mi"

    queryAPI:
      replicas: 1
      resources:
        requests:
          cpu: "10m"
          memory: "512Mi"
```

#### Scheduling and Security
```yaml
spec:
  # Node placement
  nodeSelector:
    node-type: "compute"

  # Taint tolerations
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "search"
      effect: "NoSchedule"

  # Image pull configuration
  imagePullSecret: "search-pull-secret"
  imagePullPolicy: "IfNotPresent"
```

### Operator Configuration Parameters

#### Resource Defaults (from `defaults.go`)
| Component | CPU Request | Memory Request | Memory Limit |
|-----------|-------------|----------------|--------------|
| PostgreSQL | 25m | 1Gi | 4Gi |
| API Service | 10m | 512Mi | - |
| Indexer | 10m | 32Mi | - |
| Collector | 25m | 128Mi | - |

#### Database Tuning Parameters
- **SHARED_BUFFERS**: "1GB" (25% of memory limit)
- **EFFECTIVE_CACHE_SIZE**: "2GB" (50% of memory limit)
- **WORK_MEM**: Configurable via Search CR

#### ManagedClusterAddOn Configuration
Configurable through annotations:
```yaml
metadata:
  annotations:
    "addon.open-cluster-management.io/search_memory_limit": "256Mi"
    "addon.open-cluster-management.io/search_memory_request": "64Mi"
    "addon.open-cluster-management.io/search_args": "--rediscovery-rate=60"
```

## 🎛️ Controller Implementation

### Reconciliation Flow

The main controller (`SearchReconciler`) follows this sequential pattern:

1. **Instance Retrieval** - Fetch Search custom resource
2. **Addon Framework Setup** - Initialize certificate signing (one-time)
3. **Status Updates** - Process pod-triggered reconciliations
4. **Finalization** - Handle deletion cleanup
5. **Pause Check** - Skip if `search-pause: true` annotation exists
6. **Resource Creation** - Sequential deployment:
   ```
   Service Accounts → Roles → Secrets → Services →
   Deployments → ConfigMaps → Monitoring
   ```

### Error Handling Patterns

**Fail-Fast Strategy**: Each resource creation immediately returns on failure
```go
result, err := r.createService(ctx, r.APIService(instance))
if result != nil {
    log.Error(err, "API Service setup failed")
    return *result, err
}
```

**Status Conflict Handling**: Object modification conflicts logged as "Object has been modified"

**Controller Ownership**: Uses `controllerutil.SetControllerReference()` for garbage collection

### Event Watching Configuration

```go
func (r *SearchReconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerWith("search", mgr, controller.Options{}).
        For(&searchv1alpha1.Search{}).
        Owns(&appsv1.Deployment{}, builder.WithPredicates(onlyControllerOwned)).
        Owns(&corev1.Secret{}, builder.WithPredicates(onlyControllerOwned)).
        Watches(&source.Kind{Type: &corev1.ConfigMap{}},
            &handler.EnqueueRequestForOwner{}).
        Watches(&source.Kind{Type: &corev1.Pod{}},
            &handler.EnqueueRequestForObject{},
            builder.WithPredicates(searchRelatedPods)).
        Complete(r)
}
```

**Selective Watching Reduces Reconciliation Load**:
- Deployments/Secrets: Only controller-owned resources
- ConfigMaps: Both global configs and owned instances
- Pods: Filtered by search-related labels
- ManagedClusters: Only with "hub.open-cluster-management.io" claim

## Performance Parameters

### Request Limiting

**Standard Requests:**
- Default limit: 25 concurrent requests
- Configurable via `REQUEST_LIMIT`

**Large Requests:**
- Default limit: 5 concurrent requests
- Threshold: 20 MB payload size
- Configurable via `LARGE_REQUEST_LIMIT` and `LARGE_REQUEST_SIZE`

### Timing Configuration

**Synchronization Intervals:**
- Full resync: 15 minutes (`RESYNC_PERIOD_MS`)
- Resource rediscovery: 5 minutes (`REDISCOVER_RATE_MS`)
- Health checks: 1 minute (`DB_HEALTH_CHECK_PERIOD`)

**Timeout Settings:**
- HTTP requests: 5 minutes (`HTTP_TIMEOUT`)
- Maximum retry backoff: 5 minutes (`MAX_BACKOFF_MS`)
- Slow operation logging: 1 second (`SLOW_LOG`)

### Metrics Collection

**Prometheus Metrics:**
- `RequestCount` - Total requests by cluster (counter with `managed_cluster_name` label)
- `RequestDuration` - Request processing time histogram (buckets: 0.25s to 10s)
- `RequestsInFlight` - Current active requests (gauge)
- `RequestSize` - Changes per request histogram (buckets: 50 to 200,000 changes)

## Error Patterns & Common Issues

### Database Connection Errors

**Location**: `/pkg/database/connection.go`
**Pattern**: Connection pool exhaustion or unhealthy connections
**Messages**:
- "Failed to create connection pool"
- "Connection ping failed"
**Resolution**: Check `DB_MAX_CONNS` and database availability

### Synchronization Failures

**Location**: `/pkg/clustersync/clusterSync.go`
**Pattern**: Resource availability or permission issues
**Error Flow**:
1. `stopAndStartInformer()` checks CRD availability
2. `deleteStaleClusterResources()` handles orphaned data
3. Mutex-protected `processClusterUpsert()` prevents races
**Common Causes**: Missing RBAC permissions, CRD installation issues

### Request Rate Limiting

**Location**: `/pkg/server/requestLimiter.go`, `/pkg/server/largeRequestLimiter.go`
**Pattern**: 429 Too Many Requests responses
**Thresholds**:
- Standard: 25 concurrent requests
- Large payloads (>20MB): 5 concurrent requests
**Resolution**: Increase limits or implement client-side backoff

### Resource Processing Errors

**Location**: `/pkg/clustersync/clusterSync.go`
**Pattern**: JSON marshaling/unmarshaling failures
**Flow**: Object → JSON → Typed Structure → Resource Object → Database
**Common Issues**: Invalid resource formats, schema mismatches

## Integration Interfaces

### REST API Endpoints

**Health Checks:**
- `GET /liveness` - Container liveness probe
- `GET /readiness` - Service readiness indicator

**Metrics:**
- `GET /metrics` - Prometheus-compatible metrics endpoint

**Cluster Operations:**
- `POST /aggregator/clusters/{id}/sync` - Resource synchronization endpoint
  - Accepts cluster ID as path parameter
  - Processes resource changes (add/update/delete)
  - Protected by rate limiting middleware

### Kubernetes Integration

**Resource Watching:**
- `ManagedCluster` objects - Core cluster definitions
- `ManagedClusterInfo` objects - Cluster status and metadata
- `ManagedClusterAddon` objects - Addon installations

**Addon Tracking:**
Nine monitored addon types:
- Policy management addons
- Application lifecycle addons
- Observability addons
- Security and compliance addons

**Leader Election:**
- Implements Kubernetes lease-based leader election
- Prevents duplicate processing in multi-replica deployments

### Database Schema Integration

**Resource Storage:**
```sql
-- Primary resource table with JSONB optimization
CREATE TABLE search.resources (
    -- JSONB-optimized storage for resource metadata
    -- Supports complex queries on nested JSON structures
);

-- Relationship mapping
CREATE TABLE search.edges (
    -- Resource relationship graph
    -- Enables traversal and dependency tracking
);
```

## Deployment Configuration

### Container Specifications

**Base Images:**
- Build: `registry.ci.openshift.org/stolostron/builder:go1.25-linux`
- Runtime: `registry.access.redhat.com/ubi9/ubi-minimal:latest`

**Security:**
- Non-root user (UID: 1001)
- Minimal runtime image for reduced attack surface
- TLS 1.2+ enforcement for all connections

**Resource Requirements:**
- Single compiled binary (~minimal footprint)
- Exposed port: 3010
- SSL certificate volume mount required

### Build Configuration

**Compilation:**
```bash
CGO_ENABLED=1 go build -trimpath -o main main.go
```
- CGO enabled for PostgreSQL driver compatibility
- Trimmed paths for reproducible builds

### Development Workflow

**Setup Commands:**
```bash
make setup      # Generate SSL certificates
make tests      # Run unit test suite
make run        # Local development execution
make coverage   # Generate coverage reports
make lint       # Code quality analysis
```

**Testing Infrastructure:**
```bash
make test-scale           # Headless Locust testing
make test-scale-ui        # Interactive load testing
make test-send           # Single request simulation
make show-metrics        # Metrics endpoint verification
```

### Scaling Parameters

**Horizontal Scaling:**
- Leader election prevents duplicate processing
- Multiple replicas supported with database coordination
- Stateless design enables easy scaling

**Vertical Scaling:**
- Connection pool tuning via environment variables
- Batch size configuration for memory vs. performance trade-offs
- Request limiting prevents resource exhaustion

**Load Testing Scenarios:**
- Small clusters: ~5K resources
- Medium clusters: ~100K resources
- Large clusters: ~150K resources
- 10:1 ratio of updates to full syncs
- Configurable user spawn rates and request intervals

## Debugging Guidance

### Common Troubleshooting Steps

1. **Check Configuration:**
   ```bash
   # Verify required environment variables
   echo $DB_NAME $DB_USER $DB_PASS
   ```

2. **Database Connectivity:**
   ```bash
   # Test PostgreSQL connection
   make test-send  # Should return 200 OK
   ```

3. **Metrics Inspection:**
   ```bash
   # Check current metrics
   make show-metrics
   # Look for error counters and request latencies
   ```

4. **Health Status:**
   ```bash
   curl -k https://localhost:3010/liveness
   curl -k https://localhost:3010/readiness
   ```

### Performance Analysis

**Key Metrics to Monitor:**
- Request duration histogram percentiles
- Database connection pool utilization
- Batch processing rates
- Error rate by cluster

**Optimization Strategies:**
- Increase `DB_BATCH_SIZE` for higher throughput
- Adjust `DB_MAX_CONNS` based on database capacity
- Monitor slow log for bottleneck identification
- Use load testing to validate configuration changes

### Log Analysis Patterns

**Slow Operation Detection:**
- Default threshold: 1000ms (`SLOW_LOG`)
- Logged operations indicate performance bottlenecks
- Common causes: Large batch sizes, database contention

**Error Categories:**
- Database connection failures
- Resource processing errors
- Rate limiting activation
- Leadership election conflicts

This analysis provides a comprehensive foundation for developers working with the ACM Search Indexer, enabling effective debugging, optimization, and extension of the component.