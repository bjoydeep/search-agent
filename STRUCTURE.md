# Search-Agent Skills Structure

## Workflow Skills (Primary Entry Points)

### search-architecture
**Purpose**: Multi-cluster architecture overview with live fleet composition
**MCP Integration**: Fleet size, resource distribution, cluster status
**kubectl Integration**: Component health, deployment topology
**When to use**: Understanding system design, onboarding, architecture questions

### analyze-search-issue
**Purpose**: Complete issue analysis workflow with customer impact + internal diagnostics
**MCP Integration**: Customer workload health, policy compliance, fleet context
**kubectl Integration**: Component status, logs, events, resource usage
**When to use**: Bug reports, performance issues, customer escalations

### evaluate-search-feature
**Purpose**: Feature evaluation with usage patterns + technical impact assessment
**MCP Integration**: Usage analytics, fleet composition, growth patterns
**kubectl Integration**: Current system capacity and performance baselines
**When to use**: JIRA feature analysis, epic planning, roadmap decisions

### search-monitoring
**Purpose**: Dual monitoring - customer health + system health
**MCP Integration**: Customer workload trends, policy compliance monitoring
**kubectl Integration**: Component metrics, alerting, capacity monitoring
**When to use**: Health checks, capacity planning, proactive monitoring

### search-performance
**Purpose**: Performance analysis with load patterns + bottleneck identification
**MCP Integration**: System load via resource volume and growth trends
**kubectl Integration**: Component performance metrics, resource utilization
**When to use**: Performance issues, optimization planning, capacity decisions

### search-customer-impact
**Purpose**: Customer issue analysis with business impact assessment
**MCP Integration**: Affected workloads, customer fleet analysis, impact scope
**kubectl Integration**: System status affecting customer experience
**When to use**: Customer communication, escalation decisions, impact assessment

## Component Skills (Deep Expertise)

### search-indexer
**Purpose**: PostgreSQL optimization, data ingestion, relationship computation
**Focus Areas**: Database tuning, write performance, cross-cluster relationships, scaling
**When to use**: Database issues, ingestion problems, relationship computation errors

### search-collector
**Purpose**: Resource watching, networking, multi-cluster patterns
**Focus Areas**: Kubernetes watch optimization, connectivity, heartbeat monitoring
**When to use**: Resource discovery issues, network problems, collector failures

### search-api
**Purpose**: GraphQL performance, RBAC, client integration
**Focus Areas**: Query optimization, authorization, caching, pagination
**When to use**: API performance issues, RBAC problems, client integration

### search-operator
**Purpose**: Lifecycle management, deployment orchestration
**Focus Areas**: Install/upgrade strategies, configuration management, health orchestration
**When to use**: Deployment issues, upgrade problems, configuration errors

## Supporting Structure

### scripts/
**Executable helpers that combine multiple data sources**
- `cluster-health-summary.sh` - MCP + kubectl comprehensive health
- `performance-snapshot.py` - Live performance analysis
- `customer-impact-report.sh` - MCP-based impact assessment
- `fleet-growth-analysis.py` - Resource growth trends
- `component-status-check.sh` - Cross-component kubectl health
- `database-health-check.py` - PostgreSQL performance analysis

### docs/
**Reference documentation linked by skills**
- `mcp-query-cookbook.md` - Advanced MCP query patterns
- `kubectl-quick-reference.md` - Essential kubectl by component
- `troubleshooting-decision-tree.md` - Visual troubleshooting workflow
- `architecture-diagrams/` - Visual architecture references
- `performance-benchmarks/` - Known performance characteristics

### examples/
**Complete workflow walkthroughs**
- `feature-evaluation-example.md` - Real JIRA evaluation walkthrough
- `bug-analysis-walkthrough.md` - Complete bug investigation
- `performance-investigation.md` - Performance issue diagnosis
- `customer-escalation-example.md` - Customer issue handling

### templates/
**Reusable templates for common tasks**
- `feature-analysis-template.md` - Feature evaluation template
- `bug-report-analysis.md` - Bug analysis template
- `performance-investigation.md` - Performance issue template
- `customer-communication.md` - Customer communication templates

## Usage Flow

1. **Start with workflow skills** - They provide structure and route intelligently
2. **Get live context** - MCP for customer data, kubectl for internal health
3. **Route to components** - Deep-dive when workflow skills identify component issues
4. **Reference docs/examples** - Additional patterns and detailed guidance
5. **Execute scripts** - Complex analysis combining multiple data sources

## Skill Relationships

```
analyze-search-issue ──→ search-indexer (DB issues)
                    ├──→ search-collector (network issues)
                    ├──→ search-api (query issues)
                    └──→ search-operator (deployment issues)

evaluate-search-feature ──→ All component skills (impact analysis)

search-architecture ──→ All component skills (deep component details)

search-monitoring ──→ search-performance (detailed analysis)
                 └──→ search-customer-impact (customer focus)
```