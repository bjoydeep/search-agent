---
name: search-architecture
description: ACM Search multi-cluster architecture with live fleet composition and component relationships
---

# ACM Search Architecture

## Live Fleet Overview
- Current fleet composition: !`find_resources --outputMode=summary`
- Managed clusters: !`find_resources --kind=ManagedCluster --outputMode=count --groupBy=status`
- Total indexed resources: !`find_resources --outputMode=count --groupBy=kind --limit=10`

## Component Architecture

### Operator (Hub Cluster)
**Role**: Orchestrates deployment and lifecycle of all search components
- Installs Collector on each managed cluster
- Manages Indexer and API on hub cluster
- Handles configuration distribution and updates

### Collector (Each Managed Cluster)
**Role**: Watches and reports local cluster resources
- Current collector coverage: !`find_resources --kind=ManagedCluster --outputMode=count`
- Discovers Kubernetes resources (`oc api-resources`)
- Watches for resource changes (Kubernetes watch API)
- Computes intra-cluster relationships
- Sends data to hub Indexer via secure connection

### Indexer (Hub Cluster)
**Role**: Aggregates data and computes cross-cluster relationships
- Receives data from all Collectors
- Writes to PostgreSQL database (current data: !`find_resources --outputMode=summary`)
- Computes cross-cluster resource relationships
- Monitors Collector heartbeats

### API (Hub Cluster)
**Role**: Serves search queries with RBAC enforcement
- GraphQL interface for querying aggregated data
- Enforces user permissions (users only see authorized resources)
- Serves web UI and programmatic clients (like this MCP server!)

### Database (PostgreSQL)
**Role**: Stores aggregated resource data and relationships
- Current scale: Based on live data above
- Resource data + computed relationships
- Optimized for cross-cluster queries

## Data Flow
```
Managed Clusters → Collectors → Indexer → PostgreSQL → API → Clients
                                                        ↓
                                                   MCP Server → LLMs
```

## Component Health Check (kubectl)
```bash
# Component pods
kubectl get pods -l app=search -o wide

# Indexer logs
kubectl logs -l component=search-indexer --tail=50

# Database health
kubectl exec -it $(kubectl get pods -l app=postgres -o name | head -1) -- psql -c "SELECT COUNT(*) FROM resources;"

# Collector status across clusters
kubectl get managedclusteraddons search -A
```

## Deep Component Analysis
- `/search-indexer` - PostgreSQL optimization, relationship computation, scaling
- `/search-collector` - Resource watching, networking, multi-cluster patterns
- `/search-api` - GraphQL performance, RBAC, client integration
- `/search-operator` - Lifecycle management, deployment orchestration

## Supporting Documentation
- [Component Relationships](component-relationships.md) - Detailed data flow patterns
- [Deployment Topology](deployment-topology.md) - Hub vs managed cluster placement
- [Scaling Architecture](scaling-architecture.md) - How architecture scales with fleet size