# Search-Agent Design Document

## Design Philosophy

### Hybrid Approach: Workflow + Component Skills

**Problem**: Domain expertise is scattered and context-dependent.
- Architectural knowledge lives in people's heads
- Troubleshooting patterns aren't systematized
- Feature evaluation lacks consistent framework
- Customer impact assessment is ad-hoc

**Solution**: Workflow-first skills that route to component expertise.

### Workflow Skills (How You Actually Work)
1. **Start with the problem**: "Analyze this issue", "Evaluate this feature"
2. **Get context**: Use MCP for customer data + kubectl for component health
3. **Route intelligently**: Guide to component expertise when needed

### Component Skills (Where Deep Knowledge Lives)
- **Indexer**: PostgreSQL optimization, relationship computation, scaling
- **Collector**: Kubernetes watching, networking, multi-cluster patterns
- **API**: GraphQL performance, RBAC, client integration
- **Operator**: Lifecycle management, deployment orchestration

## MCP Server Integration (Corrected Understanding)

**MCP Server Purpose**: Expose search-api data to LLMs/agents
- **Provides**: Customer fleet data, workload patterns, policy status
- **Does NOT provide**: Internal search component health/metrics

**Integration Strategy**:
- **Customer impact**: Use MCP to understand affected workloads
- **Usage patterns**: Use MCP for feature evaluation and capacity planning
- **Business context**: Use MCP for customer communication and prioritization
- **Internal health**: Use kubectl/logs/metrics/Prometheus for component diagnosis

## Directory Structure Rationale

### Why This Structure?

**Skills at the core** (`.claude/skills/`):
- Everything starts with skills - they're the primary interface
- Both MCP queries and kubectl commands live directly in skills
- Supporting files provide additional detail when needed

**Scripts for complex operations** (`scripts/`):
- Executable helpers that combine multiple data sources
- Called by skills via `!` command notation
- Reusable across multiple skills

**Documentation for reference** (`docs/`):
- Detailed patterns linked from skills
- Architecture diagrams for visual reference
- Performance benchmarks for capacity decisions

**Examples for learning** (`examples/`):
- Complete workflow walkthroughs
- Show how to use skills in real scenarios
- Template for onboarding new team members

## Key Design Decisions

### 1. Workflow-First Entry Points
Users think: "I need to analyze this bug" not "I need indexer expertise"
Workflow skills provide structure and route to component knowledge.

### 2. Live Data Integration
Static knowledge becomes stale. Skills use live MCP data for context and kubectl for operational health.

### 3. Component Routing Pattern
Workflow skills assess and route: "This looks like an indexer issue, use `/search-indexer`"

### 4. Hybrid Context Sources
- **Customer perspective**: MCP server (what customers experience)
- **Operational perspective**: kubectl/monitoring (internal component health)

### 5. Scalable Pattern
This structure becomes template for governance-agent, security-agent, etc.
Eventually consolidates into acm-agent for cross-pillar decisions.

## Future Evolution

1. **Prove the pattern** with search-agent
2. **Replicate across pillars** (governance, security, compliance)
3. **Consolidate** into acm-agent with cross-pillar capabilities
4. **Scale organizationally** - teams maintain their pillar expertise

## Usage Patterns

### For Issue Analysis
1. Start with `/analyze-search-issue`
2. Get live customer impact via MCP
3. Get internal health via kubectl
4. Route to component skill for deep analysis

### For Feature Evaluation
1. Start with `/evaluate-search-feature`
2. Understand current usage patterns via MCP
3. Assess technical impact across components
4. Consider scaling implications based on fleet size

### For Architecture Questions
1. Use `/search-architecture` for overview + live context
2. Deep-dive with component skills as needed
3. Reference docs for detailed patterns