---
name: evaluate-search-feature
description: Evaluate JIRA features/epics against ACM Search architecture, usage patterns, and constraints
disable-model-invocation: true
argument-hint: [JIRA-123]
---

Evaluate JIRA feature: $ARGUMENTS

## 1. Current Usage Context (MCP)

### Fleet Composition & Scale
- Current fleet size: !`find_resources --outputMode=summary`
- Resource type distribution: !`find_resources --outputMode=count --groupBy=kind --limit=20`
- Cluster distribution: !`find_resources --kind=ManagedCluster --outputMode=count --groupBy=status`

### Customer Usage Patterns
- Most active namespaces: !`find_resources --outputMode=count --groupBy=namespace --limit=10`
- Recent resource growth: !`find_resources --ageNewerThan=7d --outputMode=count --groupBy=kind`
- Label usage patterns: !`find_resources --labelSelector=app --outputMode=count --limit=10`

## 2. Feature Analysis Framework

### Business Impact Assessment
- **Customer benefit**: How many customers affected by current usage patterns?
- **Usage alignment**: Does this match actual customer workflows?
- **Priority justification**: Based on fleet composition and usage data above

### Technical Impact Assessment

#### **Architecture Impact**
- Which components affected? (Operator/Collector/Indexer/API)
- Does it change data flow between components?
- Any new dependencies or integration points?

#### **Scalability Assessment**
- Impact on known bottlenecks? (see `/search-performance`)
- New scaling concerns based on current fleet size?
- Database growth implications based on usage patterns?

#### **Performance Considerations**
- Query complexity impact on API layer?
- Indexer processing overhead for new data types?
- Collector resource usage on managed clusters?

## 3. Implementation Complexity

### Cross-Component Analysis
- **Operator changes**: Deployment, configuration, lifecycle
- **Collector changes**: Resource watching, data collection
- **Indexer changes**: Data processing, relationship computation
- **API changes**: GraphQL schema, query optimization
- **Database changes**: Schema updates, migration complexity

### Integration Testing Scope
- Multi-cluster testing requirements
- Performance testing with current scale
- Backward compatibility considerations

## 4. Effort Estimation

### Development Effort
- Component-specific development complexity
- Cross-component integration work
- Testing and validation requirements

### Deployment Considerations
- Upgrade strategy for existing fleet
- Configuration migration requirements
- Rollback complexity

## 5. Risk Assessment

### Customer Impact Risks
- Potential performance degradation during deployment
- Data consistency during migration
- User experience changes

### Operational Risks
- Increased operational complexity
- New failure modes
- Support and troubleshooting impact

## Component Deep-Dive References
- `/search-indexer` - Database and ingestion impact analysis
- `/search-collector` - Resource collection and networking impact
- `/search-api` - Query and performance impact
- `/search-operator` - Deployment and lifecycle impact

## Supporting Documentation
- [Usage Analysis](usage-analysis.md) - MCP query patterns for feature evaluation
- [Technical Impact](technical-impact.md) - Architecture impact assessment framework
- [Effort Estimation](effort-estimation.md) - Cross-component estimation methodology