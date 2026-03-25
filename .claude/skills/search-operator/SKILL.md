---
name: search-operator
description: ACM Search operator lifecycle management, deployment orchestration, and addon framework integration
---

# Search Operator Deep Dive

## Source Code Repository
**GitHub**: https://github.com/stolostron/search-v2-operator

### Key Source Files & Patterns
- **Operator controllers**: `controllers/` - Search CR reconciliation and component lifecycle
- **Component deployments**: `pkg/deployments/` - Indexer, API, PostgreSQL deployment logic
- **Addon integration**: `pkg/addons/` - ManagedClusterAddOn configuration and management
- **Configuration management**: `pkg/config/` - Search CR validation and default configuration
- **Operator main**: `main.go` - Operator initialization and controller manager setup

### Code Exploration Tips
- Start with `main.go` for operator initialization and controller registration
- Review `controllers/search_controller.go` for main reconciliation logic
- Check `pkg/deployments/` for component deployment patterns
- Look at `pkg/addons/addon.go` for ManagedClusterAddOn integration

## Current Operator Status
- Search operator deployment: `kubectl get pods -l control-plane=search-controller-manager -o wide`
- Active Search CRs: `kubectl get search -A`
- ManagedClusterAddOn status: !`find_resources --kind=ManagedClusterAddOn --name=search`
- Managed cluster coverage: !`find_resources --kind=ManagedCluster --outputMode=count --groupBy=status`

## Core Architecture

### Operator Deployment Chain
```
ACM Installer (Multicluster Hub) → Search Operator → Search CR → Components
        ↓                              ↓              ↓           ↓
Default Configuration            Reconciliation   Validation   Deployments
                                      ↓              ↓           ↓
                              Leader Election   Config Mgmt   Addon Setup
                                      ↓              ↓           ↓
                              Component Health   Status Update  Collector Deploy
```

### Technical Implementation
- **Controller Runtime**: Kubernetes controller-runtime framework for reconciliation
- **Leader Election**: Single-instance processing with Kubernetes-native coordination
- **CR Validation**: Search custom resource validation and defaulting webhooks
- **Component Orchestration**: Manages Indexer, API, PostgreSQL deployment lifecycle
- **Addon Framework**: Integration with ACM Server Foundation for collector deployment

### Deployment Patterns
- **Hub Components**: Indexer, API, PostgreSQL deployed directly on hub cluster
- **Managed Cluster Integration**: ManagedClusterAddOn deploys collectors via addon framework
- **Configuration Distribution**: ConfigMaps and Secrets for component configuration
- **Health Monitoring**: Component status aggregation and Search CR status updates

## Common Issues & Solutions

### Search CR Reconciliation Issues
**Symptoms:**
- Search CR stuck in pending or error state
- Component deployments not creating or updating
- Configuration changes not propagating

**Diagnostic Commands:**
```bash
# Operator pod status and logs
kubectl get pods -l control-plane=search-controller-manager -o wide
kubectl logs -l control-plane=search-controller-manager --tail=200

# Search CR status and conditions
kubectl get search -A -o yaml | grep -A10 -B5 "status\|conditions"

# Recent operator events and reconciliation
kubectl get events --field-selector involvedObject.kind=Search --sort-by=.lastTimestamp | tail -10
```

**Common Causes:**
- [TODO: Add Search CR validation failures and fixes]
- [TODO: Add reconciliation loop issues and debugging]
- [TODO: Add component deployment failure patterns]

### Component Deployment Problems
**Symptoms:**
- Indexer, API, or PostgreSQL pods not starting
- Component configuration issues
- Resource limit or permission problems

**Diagnostic Commands:**
```bash
# Component deployment status
kubectl get pods -l app=search-indexer,app=search-api,app=postgres -o wide

# Component-specific deployment issues
kubectl get deployments -l app.kubernetes.io/part-of=search -o wide
kubectl describe deployment search-indexer
kubectl describe deployment search-api

# Configuration and secrets
kubectl get configmaps -l app.kubernetes.io/part-of=search
kubectl get secrets -l app.kubernetes.io/part-of=search
```

**Resolution Patterns:**
- [TODO: Add component deployment troubleshooting steps]
- [TODO: Add configuration validation and fixes]
- [TODO: Add resource requirement optimization]

### ManagedClusterAddOn Issues
**Symptoms:**
- Search collectors not deploying to managed clusters
- Addon status showing as degraded or unavailable
- Collector deployment inconsistencies

**Diagnostic Commands:**
```bash
# ManagedClusterAddOn status across all clusters
kubectl get managedclusteraddons search -A -o custom-columns="CLUSTER:.metadata.namespace,STATUS:.status.conditions[-1].type,REASON:.status.conditions[-1].reason,MESSAGE:.status.conditions[-1].message"

# Addon framework integration
kubectl get klusterletaddonconfigs -A | grep search
kubectl get manifestworks -A | grep search

# Addon controller logs
kubectl logs -n open-cluster-management-hub -l app=klusterlet-addon-controller --tail=200 | grep search
```

**Troubleshooting Patterns:**
- [TODO: Add addon framework debugging workflows]
- [TODO: Add ManagedClusterAddOn lifecycle issues]
- [TODO: Add cross-cluster deployment validation]

### Leader Election & High Availability
**Symptoms:**
- Multiple operator instances running
- Inconsistent reconciliation behavior
- Leader election failures

**Diagnostic Commands:**
```bash
# Leader election status
kubectl get lease -n open-cluster-management search-controller-manager -o yaml

# Operator replica count and status
kubectl get deployment -l control-plane=search-controller-manager -o wide

# Leader election events and transitions
kubectl get events --field-selector involvedObject.kind=Lease,involvedObject.name=search-controller-manager --sort-by=.lastTimestamp | tail -10
```

**HA Patterns:**
- [TODO: Add leader election troubleshooting]
- [TODO: Add operator scaling and HA configuration]
- [TODO: Add reconciliation conflict resolution]

## Live Operator Health Analysis

### Reconciliation Performance
```bash
# Operator controller metrics and performance
kubectl logs -l control-plane=search-controller-manager --tail=300 | grep -E "(reconcile|duration|error)"

# Search CR reconciliation frequency
kubectl get events --field-selector involvedObject.kind=Search --sort-by=.lastTimestamp | tail -20
```

### Component Health Monitoring
```bash
# Overall search system health from operator perspective
kubectl get search -A -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'

# Component deployment readiness
kubectl get deployments -l app.kubernetes.io/part-of=search -o jsonpath='{.items[*].status.readyReplicas}'
```

### Addon Framework Integration
```bash
# ManagedClusterAddOn deployment success rate
kubectl get managedclusteraddons search -A --no-headers | grep -c Available
kubectl get managedclusters --no-headers | wc -l  # Total clusters for comparison

# Addon framework controller health
kubectl get pods -n open-cluster-management-hub -l app=klusterlet-addon-controller -o wide
```

## Cross-Component Routing

### **Component deployment failures** → Component-specific skills
- **Indexer deployment issues** → `/search-indexer`
- **API deployment issues** → `/search-api`
- **Collector deployment via addon** → `/search-collector`

### **Platform integration problems** → Platform skills
- **ACM Installer configuration** → `acm-installer` (future skill)
- **Addon framework issues** → `acm-server-foundation` (future skill)
- **Hub cluster resource problems** → `/search-architecture`

### **Performance and scaling** → `/search-performance`
- Operator resource usage and scaling decisions
- Component deployment optimization for large fleets
- Reconciliation performance tuning

## Operator Configuration & Tuning

### Search CR Customization
- **Component resource requirements**: CPU, memory, storage configuration
- **Database configuration**: PostgreSQL settings and persistence options
- **API configuration**: Authentication, RBAC, and service exposure
- **Collector configuration**: Resource limits and collection scope

### Performance Tuning
- **Reconciliation intervals**: Controller reconciliation frequency optimization
- **Leader election configuration**: Lease duration and renewal intervals
- **Component scaling**: Replica counts and resource allocation
- **Addon deployment batching**: Managing large-scale collector deployments

### High Availability Patterns
- **Operator redundancy**: Multi-replica operator deployment strategies
- **Component HA**: Database clustering and API load balancing
- **Cross-cluster resilience**: Addon framework fault tolerance
- **Backup and recovery**: Search system backup and restore procedures

---

## TODO: Questions for Enhancement

Please help enhance this skill by answering:

### **1. Operator Deployment Issues?**
- What are your most common Search operator deployment problems?
- Reconciliation failures and debugging strategies you've developed?
- Component deployment ordering and dependency management approaches?

### **2. Search CR Configuration?**
- Common Search CR customization patterns for different environments?
- Validation failures and configuration debugging workflows?
- Default configuration optimization for different fleet sizes?

### **3. ManagedClusterAddOn Integration?**
- Common addon framework issues and resolution patterns?
- Collector deployment failures across managed clusters?
- Cross-cluster deployment validation and troubleshooting approaches?

### **4. Scaling & Performance?**
- Operator scaling strategies for large ACM deployments?
- Reconciliation performance optimization techniques?
- Component resource sizing based on fleet characteristics?

### **5. Upgrade & Migration?**
- Search operator upgrade procedures and rollback strategies?
- Component version management and compatibility validation?
- Migration patterns for configuration changes?

### **6. Monitoring & Troubleshooting?**
- Key operator metrics and monitoring approaches?
- Automated health checks and alerting strategies?
- Log analysis patterns for operator debugging?

Please update this skill with your operator management experience and deployment patterns!

---

## Code Analysis & Implementation Details

**[📋 Code Analysis](code-analysis.md)** - Comprehensive source code analysis including:
- Controller reconciliation logic and patterns
- Custom Resource Definition (CRD) structure and validation
- Component deployment configurations and templates
- Addon framework integration and configuration
- Performance parameters and scaling options
- Error patterns and troubleshooting workflows