# ACM Search Operator v2 - Comprehensive Code Analysis

## Repository Overview

**Repository**: https://github.com/stolostron/search-v2-operator
**Purpose**: Kubernetes operator for deploying Open Cluster Management (OCM) Search v2 components
**Technology Stack**: Go (90.7%), Shell (5.4%), Makefile (3.1%)
**Framework**: Built with Kubebuilder and controller-runtime

## 📁 Source File Navigation

### Core Controller Files
- **`main.go`** - Operator entry point with manager initialization
- **`controllers/search_controller.go`** (20KB) - Main reconciliation logic
- **`controllers/common.go`** (22KB) - Shared utilities and configuration patterns
- **`controllers/defaults.go`** - Default resource requirements and configuration

### Component Deployment Files
```
controllers/
├── create_apiservice.go          # API Service deployment
├── create_apideployment.go       # API Deployment configuration
├── create_collectordeploy.go     # Collector deployment logic
├── create_indexerdeploy.go       # Indexer deployment setup
├── create_pgdeployment.go        # PostgreSQL deployment
├── create_pgservice.go           # PostgreSQL Service
├── create_pgsecret.go            # Database credentials management
├── create_pgconfigmap.go         # PostgreSQL configuration
├── create_pvc.go                 # Persistent Volume Claims
└── create_sa.go                  # Service Account creation
```

### Addon Integration
```
addon/
├── addon.go                      # ManagedClusterAddOn implementation
├── addon_test.go                 # Comprehensive addon tests
└── manifests/                    # Kubernetes manifests for managed clusters
```

### Configuration & Deployment
```
config/
├── crd/bases/                    # Custom Resource Definitions
├── manager/manager.yaml          # Operator deployment configuration
├── samples/                      # Example configurations
└── rbac/                         # Role-based access control
```

## 🔧 Configuration Options

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

## 🚀 Component Deployment

### PostgreSQL Deployment Pattern

**Storage Strategy**:
- PVC with ReadWriteOnce access mode
- Recreate deployment strategy (not rolling updates)
- 300-second termination grace period
- Mount point: `/var/lib/pgsql/data`

**Initialization Scripts** (via ConfigMap):
- `postgresql-pre-start.sh` - Pre-startup tasks
- `postgresql-start` - Startup configuration
- `postgresql-cfg` - Configuration files

**Security Configuration**:
```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

### API Service Deployment

**Service Configuration**:
- Port 4010 (TCP)
- Selector: `name: search-api`
- OpenShift cert annotation: `service.beta.openshift.io/serving-cert-secret-name`

**Resource Allocation**: 10m CPU, 512Mi memory

### Indexer and Collector Deployments

**Scaling Restrictions**:
- Both forced to 1 replica despite CR configuration
- Prevents architectural violations
- Collector: 25m CPU, 128Mi memory
- Indexer: 10m CPU, 32Mi memory

## 🔌 Addon Integration

### ManagedClusterAddOn Configuration

**Certificate Management**:
```go
RegistrationOption{
    CSRConfigurations: agent.KubeClientSignerConfigurations(),
    CSRApproveCheck:   agent.DefaultCSRApprover(),
}
```
- Automatic CSR generation with addon identity
- Auto-approval workflow eliminates manual certificate steps

**RBAC Setup**:
```go
func createOrUpdateRoleBinding(cluster, namespace string) {
    // Creates RoleBinding in cluster namespace
    // Binds addon service accounts to ClusterRoles
    // Deep equality checks minimize reconciliation
}
```

**Configuration Injection**:
- Memory limits via annotations (validated with regex)
- Runtime behavior: rediscovery rate, heartbeat intervals
- Custom container arguments through `search_args`

**Platform Detection**:
- Kubernetes distribution detection
- Conditional Prometheus enablement
- OpenShift vs standard cluster awareness

### Helm Value Generation

The addon framework chains:
1. Custom logic functions
2. Annotation-based configuration
3. Deployment configs
4. Merged Helm values for manifest generation

## ⚡ Performance Parameters

### Operator Performance
- **Resource Requests**: 10m CPU, 256Mi memory
- **Leader Election**: Enabled for HA deployments
- **Health Probes**:
  - Liveness: `/healthz` (15s initial delay)
  - Readiness: `/readyz` (5s initial delay)

### Reconciliation Timing
- **Event-driven**: Watches specific resource types
- **Filtered Events**: Predicates reduce unnecessary reconciliations
- **Pause Capability**: `search-pause: true` annotation

### Scaling Configuration
- **Database**: Single replica (architectural constraint)
- **Collector**: Single replica (data consistency)
- **API/Indexer**: Configurable but default to 1

### Database Performance Tuning
```yaml
SHARED_BUFFERS: "1GB"           # 25% of 4Gi limit
EFFECTIVE_CACHE_SIZE: "2GB"     # 50% of 4Gi limit
WORK_MEM: "configurable"        # Via Search CR
```

## ❌ Error Patterns & Troubleshooting

### Common Controller Failures

| Error Pattern | Location | Resolution |
|---------------|----------|------------|
| "API Service setup failed" | `search_controller.go` | Check service account permissions |
| "Object has been modified" | Status updates | Normal - object conflict, retry occurs |
| Pod scheduling failures | Component deployments | Verify node selector/tolerations |
| PVC creation errors | `create_pvc.go` | Check storage class availability |
| Image pull failures | All deployments | Verify imagePullSecret configuration |

### Debugging Commands

**Check Operator Status**:
```bash
kubectl get pods -n open-cluster-management -l app=search-v2-operator
kubectl logs -n open-cluster-management deployment/search-v2-operator-controller-manager
```

**Verify Search Components**:
```bash
kubectl get pods -n open-cluster-management | grep search-
# Expected pods: search-api, search-collector, search-indexer, search-postgres
```

**Check Search CR Status**:
```bash
kubectl get search search-v2-operator -o yaml
kubectl describe search search-v2-operator
```

**Managed Cluster Verification**:
```bash
kubectl get pods -n open-cluster-management-agent-addon -l app=klusterlet-addon-search
```

### Configuration Validation

**Common Misconfigurations**:
1. **Storage Class**: Verify `storageClassName` exists in cluster
2. **Resource Limits**: Ensure requests don't exceed node capacity
3. **Image References**: Check registry access and image availability
4. **RBAC**: Verify operator service account has cluster-admin equivalent

**Validation Tools**:
- CRD OpenAPI schema validation (automatic)
- Minimum replica count enforcement (>=1)
- Resource quantity pattern validation

## 📋 CRD Structure Reference

### Search Custom Resource Definition

**API Version**: `search.open-cluster-management.io/v1alpha1`
**Kind**: `Search`
**Scope**: `Namespaced`

#### Spec Schema Summary
```yaml
spec:
  # Storage configuration
  dbStorage:
    size: string                  # Kubernetes quantity (default: "10Gi")
    storageClassName: string      # Optional storage class

  # Database parameters
  dbConfig:
    name: string                  # ConfigMap reference

  # Component customization
  deployments:
    database: ComponentSpec
    indexer: ComponentSpec
    collector: ComponentSpec
    queryAPI: ComponentSpec

  # Scheduling
  nodeSelector: map[string]string
  tolerations: []Toleration

  # Registry settings
  imagePullPolicy: string
  imagePullSecret: string

  # Availability (placeholder)
  availabilityConfig:
    availabilityType: string      # "Basic" or "High" (not implemented)
```

#### ComponentSpec Structure
```yaml
ComponentSpec:
  replicas: integer               # Minimum: 1
  imageOverride: string           # Custom container image
  resources:                      # Standard Kubernetes ResourceRequirements
    requests: {}
    limits: {}
  env: []EnvVar                   # Environment variables
  arguments: []string             # Container arguments
```

#### Status Schema
```yaml
status:
  conditions: []Condition         # Standard Kubernetes conditions
  db: string                      # Database identifier
  storage: string                 # Storage system identifier
```

### Condition Types
- **Ready**: Overall operator status
- **Database**: Database component status
- **Indexer**: Indexer component status
- **Collector**: Collector component status
- **API**: API service status

## 🛠️ Development Workflow

### Required Tools
- Operator SDK v1.15+
- Go 1.19+
- Kustomize
- Kubernetes cluster access

### Code Generation Commands
```bash
# Generate code and manifests
make generate
make manifests
make bundle

# Build and deploy
make docker-build docker-push
make deploy
```

### Bundle Management
**⚠️ Critical**: Never edit `/bundle/manifests` manually. All changes must go through:
1. Update source code
2. Run `make generate; make manifests; make bundle`
3. Commit generated files

### Testing
```bash
# Run unit tests
make test

# Run addon tests specifically
go test ./addon/...

# Integration testing
make test-integration
```

## 📈 Monitoring & Observability

### Metrics Endpoints
- **Manager Metrics**: `:8080/metrics`
- **Health Check**: `:8081/healthz`
- **Readiness**: `:8081/readyz`

### Prometheus Integration
- ServiceMonitor creation for metrics collection
- OpenShift-specific certificate handling
- Alerting rules for component health

### Logging Patterns
- Structured logging via controller-runtime
- Error logging on reconciliation failures
- Status transition logging for debugging

## 🔐 Security Considerations

### Operator Security
- Non-root container execution
- Privilege escalation disabled
- Minimal capability set
- Dedicated service account

### Component Security
- All deployments run as non-root
- Read-only filesystem where possible
- Network policies (when configured)
- Secret-based credential management

### RBAC Requirements
The operator requires extensive permissions:
- Cross-namespace resource management
- Service account impersonation
- Certificate signing request management
- Addon lifecycle management

---

**Generated**: March 2026
**Repository**: https://github.com/stolostron/search-v2-operator
**Analysis Scope**: Main branch, comprehensive codebase review