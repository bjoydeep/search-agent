# ACM Search Indexer - Code Analysis

## Repository
**GitHub**: https://github.com/stolostron/search-indexer

## Source File Navigation

### Key Files and Entry Points
- **`main.go`**: Application startup, database connection, and configuration management
- **`pkg/database/connection.go`**: PostgreSQL connection pooling with pgxpool
- **`pkg/server/syncHandler.go`**: REST endpoints for collector sync requests
- **`pkg/database/sync.go`**: Core batch processing and upsert operations
- **`pkg/database/resync.go`**: Full cluster resync and relationship computation
- **`pkg/clustersync/clustersync.go`**: Leader election and hub resource integration

### Code Exploration Flow
1. Start with `main.go` → database connection setup → server startup
2. Review `pkg/database/connection.go` → connection pooling configuration
3. Check `pkg/server/syncHandler.go` → request handling and validation
4. Examine `pkg/database/sync.go` → batch processing implementation
5. Look at `pkg/database/resync.go` → relationship computation logic

## Configuration Options

### Environment Variables
```bash
# Database Configuration
DB_HOST="search-postgres"                    # PostgreSQL host
DB_PORT="5432"                              # PostgreSQL port
DB_NAME="search"                            # Database name
DB_USER="search"                            # Database username

# Performance Tuning
REQUEST_LIMIT=25                            # Max concurrent requests
LARGE_REQUEST_LIMIT=5                       # Max large requests (>20MB)
LARGE_REQUEST_SIZE=20971520                 # 20MB threshold for large requests
HTTP_TIMEOUT=300000                         # HTTP timeout in milliseconds

# Connection Pooling  
DB_MAX_CONNECTIONS=10                       # Max connections in pool
DB_MIN_CONNECTIONS=2                        # Min connections in pool
DB_CONNECTION_TIMEOUT=30000                 # Connection timeout in ms

# Batch Processing
BATCH_SIZE=2500                             # Operations per batch
MAX_BACKOFF_MS=300000                       # Max retry backoff (5 min)
RETRY_JITTER_MS=5000                        # Retry jitter in ms

# Leader Election
LEADER_ELECTION_NAMESPACE="open-cluster-management"
LEADER_ELECTION_NAME="search-indexer-lock"
```

### Configuration Files
- **Config loading**: `pkg/config/config.go` with environment variable overrides
- **Default values**: Fallback configurations when environment variables not set
- **Validation**: Required configuration validation in `main.go`

## Database Implementation

### Connection Pooling (`pkg/database/connection.go`)
```go
// pgxpool configuration
poolConfig.MaxConns = 10                    // Maximum connections
poolConfig.MinConns = 2                     // Minimum connections  
poolConfig.MaxConnLifetime = 5 * time.Minute // Connection lifecycle
poolConfig.MaxConnIdleTime = 1 * time.Minute // Idle timeout

// Health check callbacks
poolConfig.AfterConnect = afterConnect       // Validate connection
poolConfig.BeforeAcquire = beforeAcquire    // Pre-acquisition check
```

### Batch Processing (`pkg/database/sync.go`)
```go
// Batch size configuration
const DEFAULT_BATCH_SIZE = 2500

// Conditional upsert pattern
INSERT INTO search.resources (uid, cluster, data) 
VALUES ($1, $2, $3) 
ON CONFLICT (uid, cluster) 
DO UPDATE SET data = $3 
WHERE search.resources.data != $3
```

### Schema Design
```sql
-- Resources table (JSONB documents)
CREATE TABLE search.resources (
    uid TEXT NOT NULL,
    cluster TEXT NOT NULL,
    data JSONB NOT NULL,
    PRIMARY KEY (uid, cluster)
);

-- Edges table (relationship mappings)
CREATE TABLE search.edges (
    sourceUID TEXT NOT NULL,
    sourceCluster TEXT NOT NULL,
    destUID TEXT NOT NULL,
    destCluster TEXT NOT NULL,
    edgeType TEXT NOT NULL,
    PRIMARY KEY (sourceUID, sourceCluster, destUID, destCluster, edgeType)
);

-- Indexes for performance
CREATE INDEX resources_data_gin ON search.resources USING GIN (data);
CREATE INDEX edges_source_btree ON search.edges (sourceCluster, sourceUID);
```

## Performance Parameters

### Request Handling (`pkg/server/syncHandler.go`)
```go
// Concurrency limits
requestLimiter := make(chan struct{}, 25)      // General requests
largeRequestLimiter := make(chan struct{}, 5)  // Large requests

// Request size classification
const LARGE_REQUEST_SIZE = 20 * 1024 * 1024   // 20MB threshold

// Content-Length based routing
if r.ContentLength > LARGE_REQUEST_SIZE {
    // Route to large request limiter
}
```

### Batch Processing Optimization
```go
// Binary search retry on batch failures
func processBatchWithRetry(batch []Resource) error {
    for batchSize := len(batch); batchSize > 0; batchSize /= 2 {
        if err := processBatch(batch[:batchSize]); err == nil {
            return processBatchWithRetry(batch[batchSize:])
        }
    }
}

// Memory management for large batches
runtime.GC()  // Force garbage collection after large operations
```

### Connection Management
```go
// Connection jitter to prevent fleet synchronization
jitter := time.Duration(rand.Intn(60)) * time.Second

// Exponential backoff with max limit
backoff := min(baseBackoff * 2^retries, MAX_BACKOFF_MS)
```

## Error Patterns and Locations

### Common Error Messages
```go
// Connection failures (pkg/database/connection.go)
"Unable to connect to database: %+v"
"Database connection failed after retries"

// Batch processing errors (pkg/database/sync.go)  
"Batch processing failed: %v"
"Binary search retry exhausted for batch"

// Request limiting (pkg/server/syncHandler.go)
"Request rejected: too many concurrent requests"
"Large request rejected: exceeds size limit"

// Leader election (pkg/clustersync/clustersync.go)
"Failed to acquire leader election lock"
"Leader election lost, stopping cluster sync"
```

### Debugging Patterns
```bash
# Connection pool status
grep -E "(connection|pool|acquire)" /var/log/indexer.log

# Batch processing issues
grep -E "(batch|retry|binary.*search)" /var/log/indexer.log

# Memory and performance issues
grep -E "(memory|GC|heap|timeout)" /var/log/indexer.log

# Request limiting and load issues
grep -E "(limit|reject|concurrent)" /var/log/indexer.log
```

## Integration Interfaces

### Metrics Endpoints (Port 3010)
```go
// Prometheus metrics available at /metrics
search_indexer_request_count{managed_cluster_name}
search_indexer_request_duration{code}  
search_indexer_requests_in_flight
search_indexer_request_size

// Health endpoints
/liveness    // Basic liveness probe
/readiness   // Readiness probe
```

### API Endpoints (`pkg/server/server.go`)
```go
// Sync endpoint for collectors
POST /aggregator/clusters/{id}/sync
Content-Type: application/json

// Request/response format
type SyncRequest struct {
    AddResources    []Resource `json:"addResources"`
    UpdateResources []Resource `json:"updateResources"`  
    DeleteResources []string   `json:"deleteResources"`
}
```

### Database Interfaces
```go
// Connection pool access
func GetConnPool() *pgxpool.Pool

// Batch operations
func ProcessSyncRequest(cluster string, request SyncRequest) error
func ProcessResync(cluster string) error

// Relationship computation
func ComputeEdges(resources []Resource) []Edge
```

## Deployment Configuration

### Resource Requirements
```yaml
# Recommended limits
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "2Gi"  
    cpu: "1000m"

# Scaling triggers
- Memory usage > 80% (batch processing intensive)
- CPU usage > 70% (relationship computation intensive)
- Request queue depth > 20 (concurrent load)
```

### Kubernetes Configuration
```yaml
# Leader election RBAC
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]

# Service configuration
apiVersion: v1
kind: Service
spec:
  ports:
  - port: 3010
    name: metrics
    protocol: TCP
```

### Scaling Parameters
```bash
# Horizontal scaling triggers
HPA_CPU_THRESHOLD=70                        # CPU percentage
HPA_MEMORY_THRESHOLD=80                     # Memory percentage
HPA_MIN_REPLICAS=1                          # Minimum replicas (leader election)
HPA_MAX_REPLICAS=1                          # Maximum replicas (single instance)

# Vertical scaling indicators
- Connection pool exhaustion (increase DB_MAX_CONNECTIONS)
- Batch timeout errors (increase BATCH_SIZE or reduce it)
- Memory pressure (increase resource limits)
```

## Performance Tuning Guide

### Connection Pool Tuning
```go
// For small fleets (<50 clusters)
DB_MAX_CONNECTIONS=5
DB_MIN_CONNECTIONS=1

// For large fleets (>100 clusters) 
DB_MAX_CONNECTIONS=15
DB_MIN_CONNECTIONS=5
```

### Batch Size Optimization
```bash
# Small clusters (few resources)
BATCH_SIZE=1000                             # Faster processing

# Large clusters (many resources)  
BATCH_SIZE=5000                             # Better throughput

# Mixed environments
BATCH_SIZE=2500                             # Balanced default
```

### Memory Management
```go
// Force GC after large operations
defer runtime.GC()

// Monitor heap growth
runtime.ReadMemStats(&memStats)
if memStats.HeapAlloc > threshold {
    // Trigger cleanup or reduce batch size
}
```