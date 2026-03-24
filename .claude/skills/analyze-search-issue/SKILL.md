---
name: analyze-search-issue
description: Analyze ACM Search issues with live customer impact assessment and component diagnostics
disable-model-invocation: true
argument-hint: [issue description or JIRA]
---

Analyze ACM Search issue: $ARGUMENTS

## 1. Customer Impact Assessment (MCP)

### Current Customer Health
- Failed customer workloads: !`find_resources --kind=Pod --status=Failed,Error,CrashLoopBackOff --ageNewerThan=2h`
- Non-compliant policies: !`find_resources --textSearch=NonCompliant --ageNewerThan=2h`
- Unhealthy clusters: !`find_resources --kind=ManagedCluster --status=NotReady,Unknown`

### Fleet Context
- Total fleet size: !`find_resources --outputMode=summary`
- Recent resource activity: !`find_resources --ageNewerThan=1h --outputMode=count --groupBy=cluster`

## 2. System Health Assessment (kubectl)

```bash
# Component status
kubectl get pods -l app=search -o wide

# Recent errors across components
kubectl get events --sort-by=.lastTimestamp | grep -i error | tail -10

# Resource usage
kubectl top pods -l app=search
```

## 3. Issue Classification & Routing

Based on symptoms and live data above:

### **Customer-Facing Issues** → Use `/search-customer-impact`
- Search results missing or stale
- Performance degradation for users
- Authorization/RBAC problems

### **Indexer Issues** → Use `/search-indexer`
- Database performance problems
- Write throughput issues
- Relationship computation errors
- PostgreSQL connection issues

### **Collector Issues** → Use `/search-collector`
- Resource discovery failures
- Cross-cluster connectivity problems
- Heartbeat/health check failures
- High resource usage on managed clusters

### **API Issues** → Use `/search-api`
- GraphQL query performance
- Response time degradation
- Client connection issues

### **Operator Issues** → Use `/search-operator`
- Deployment/upgrade problems
- Configuration management issues
- Component lifecycle problems

## 4. Quick Resolution Patterns

[TODO: Common quick fixes by component]

## 5. Escalation Criteria

[TODO: When to escalate vs investigate further]

## Supporting Documentation
- [Customer Impact Triage](customer-impact-triage.md) - MCP-based impact assessment patterns
- [Internal Diagnostics](internal-diagnostics.md) - kubectl/logs/metrics patterns
- [Resolution Patterns](resolution-patterns.md) - Common fixes by component