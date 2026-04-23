# Search-Agent Project Instructions

## Project Context
This is the **ACM Search monitoring and performance assessment system**. You're working with a comprehensive skill-based architecture that monitors search components (indexer, API, collector, operator) in OpenShift/ACM environments.

## Access Permissions
- **Project scope only**: Work within `/Users/jbanerje/code/search-agent/` directory
- **Kubernetes cluster access**: Use kubectl for monitoring data collection
- **No system files**: Avoid `~/`, `/etc`, `/var`, or credential directories
- **Read-only focus**: Prioritize monitoring and analysis over modifications

## Key Architecture
- **Orchestration**: `search-architecture` skill coordinates everything
- **Impact Assessment**: Specialized skills with Prometheus + kubectl integration
- **Separation of Concerns**: SKILL.md (methodology) + scripts/ (implementation)
- **JSON Integration**: Cross-skill communication via structured reports

## Common Tasks
- **System assessment**: Use `search-architecture` skill for intelligent routing
- **Component deep dive**: Use specific impact skills for detailed analysis
- **Performance investigation**: Check `monitoring_data/impacts/` for recent assessments
- **Troubleshooting**: Follow audit trails in execution logs

## Data Sources
- **Prometheus metrics**: Primary performance data via OpenShift monitoring
- **kubectl queries**: Component health, deployment status, resource usage
- **Health endpoints**: Direct component metrics and status
- **Assessment history**: JSON reports for trend analysis

This system has **proven implementation** - use existing patterns rather than theoretical approaches.