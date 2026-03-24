# ACM Search Agent

Expert knowledge base and skills for ACM Search system development, troubleshooting, and architecture decisions.

## Philosophy: Workflow-First with Component Deep-Dive

This agent uses a **hybrid approach**:

1. **Start with workflows** - Issue analysis, feature evaluation, monitoring
2. **Route to component expertise** - Indexer, Collector, API, Operator deep knowledge when needed
3. **Combine live data** - MCP server for customer fleet data + kubectl/monitoring for internal health
4. **Preserve expertise** - Architectural knowledge and troubleshooting patterns as code

## MCP Integration

The MCP server (`~/code/search-mcp-server/golang/`) provides access to **customer fleet data**:
- Managed cluster resources (Pods, Services, etc.)
- Policy compliance status across clusters
- Resource usage patterns and trends
- Customer workload health

**NOT for internal ACM Search component monitoring** - use traditional operational tools for that.

## Quick Start

### Workflow Skills (Primary Entry Points)
- `/search-architecture` - System architecture with live fleet composition
- `/analyze-search-issue` - Complete issue analysis workflow
- `/evaluate-search-feature` - Feature impact assessment with usage data
- `/search-monitoring` - Customer health + system health monitoring
- `/search-performance` - Performance analysis and optimization
- `/search-customer-impact` - Customer issue analysis and communication

### Component Skills (Deep Expertise)
- `/search-indexer` - PostgreSQL, data ingestion, relationship computation
- `/search-collector` - Kubernetes watching, networking, multi-cluster patterns
- `/search-api` - GraphQL, RBAC, performance, client integration
- `/search-operator` - Lifecycle management, deployment, orchestration

## Architecture Overview

```
Managed Clusters → Collectors → Indexer → PostgreSQL → API → Clients
                                                        ↓
                                                   MCP Server → LLMs/Skills
```

**Operator** orchestrates the entire system deployment and lifecycle.

## Usage Examples

**Analyze a customer issue:**
```
/analyze-search-issue "Search returns stale results after cluster updates"
```

**Evaluate a feature request:**
```
/evaluate-search-feature SEARCH-456
```

**Check system architecture with current fleet size:**
```
/search-architecture
```

**Deep-dive into indexer performance:**
```
/search-indexer
```

## Repository Structure

- `.claude/skills/` - All expertise skills (workflow + component)
- `scripts/` - Executable helpers for live data analysis
- `docs/` - Reference documentation and architecture diagrams
- `examples/` - Complete workflow walkthroughs
- `templates/` - Reusable analysis templates

## Development

This repository captures institutional knowledge about ACM Search. As patterns emerge or architecture evolves, update the relevant skills.

Future: Replicate this pattern for other ACM pillars (governance-agent, security-agent, etc.) and consolidate into acm-agent.