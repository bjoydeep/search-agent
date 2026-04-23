# Search-Agent Skills Structure

## Architecture Overview

Our skills follow a **separation of concerns** design where:
- **SKILL.md** = Methodology and domain knowledge  
- **scripts/** = Implementation and data collection
- **JSON reports** = Programmatic integration between skills

## Orchestration Layer (Primary Entry Point)

### search-architecture
**Purpose**: Intelligent orchestrator - routes symptoms, coordinates assessments, synthesizes insights
**Implementation**: 
- `scripts/orchestrate-assessment.sh` - Smart assessment routing based on symptoms
- `scripts/correlate-results.sh` - Cross-impact analysis and pattern recognition  
- `scripts/route-symptoms.sh` - Symptom-based routing guidance
**Integration**: Coordinates all impact skills and provides architectural reasoning
**When to use**: System-wide analysis, complex performance issues, architectural guidance

## Impact Assessment Skills (Specialized Analysis)

### search-api-impact
**Purpose**: GraphQL query latency, RBAC load, response time degradation assessment
**Implementation**: Modular scripts with Prometheus metrics + health endpoint analysis
**Focus**: API performance, authentication overhead, client patterns, WebSocket health
**When to use**: Policy deployment events, query slowness, authentication issues

### search-indexer-impact  
**Purpose**: Database pressure, batch processing, relationship computation performance assessment
**Implementation**: Prometheus metrics + comprehensive PostgreSQL diagnostics
**Focus**: Request processing, database health, capacity utilization, resync patterns
**When to use**: ManagedCluster events, database issues, ingestion problems

### search-collector-impact
**Purpose**: Cross-cluster connection stress, networking, fleet-wide collection performance
**Implementation**: Connection analysis, resource utilization, cross-cluster latency testing
**Focus**: Network connectivity, connection pool exhaustion, managed cluster fleet health
**When to use**: New cluster additions, network issues, collector deployment problems

### search-operator-impact
**Purpose**: Reconciliation performance, component deployment, addon management assessment  
**Implementation**: Controller metrics, deployment analysis, resource consumption tracking
**Focus**: Operator stability, component lifecycle, ManagedClusterAddOn distribution
**When to use**: Operator upgrades, component deployment issues, reconciliation delays

## Component Expertise Skills (Deep Knowledge)

### search-indexer
**Purpose**: PostgreSQL optimization, batch processing strategies, relationship computation
**Focus**: Database tuning, write performance, cross-cluster relationships, scaling patterns
**Integration**: Provides deep expertise for indexer-impact assessments

### search-api
**Purpose**: GraphQL performance patterns, RBAC optimization, client integration strategies  
**Focus**: Query optimization, authorization patterns, caching, pagination, real-time features
**Integration**: Provides deep expertise for api-impact assessments

### search-collector
**Purpose**: Resource watching optimization, networking patterns, multi-cluster architecture
**Focus**: Kubernetes informers, connectivity patterns, heartbeat monitoring, channel processing
**Integration**: Provides deep expertise for collector-impact assessments

### search-operator
**Purpose**: Lifecycle management, deployment orchestration, addon framework integration
**Focus**: Installation strategies, configuration management, reconciliation patterns
**Integration**: Provides deep expertise for operator-impact assessments

## Implementation Architecture

### Separation of Concerns Pattern
```
SKILL.md (Methodology)  +  scripts/ (Implementation)  =  Complete Skill
     ↓                           ↓                           ↓
Domain Knowledge        +   Data Collection        =   Actionable Insights
```

### Script Architecture (Per Impact Skill)
```
scripts/
├── generate-assessment.sh      # Main orchestrator
├── prometheus-metrics.sh       # Core metrics collection  
├── performance-analysis.sh     # Processing efficiency
├── [component]-health.sh       # Component-specific health
└── [specialized].sh           # Domain-specific analysis
```

### Integration Flow
```
User Symptom → search-architecture → Impact Skills → JSON Reports → Correlation → Unified Insights
```

## Key Architectural Decisions

### **Synchronous vs Asynchronous Data Pipeline**
- **Reality**: Synchronous push from collector → indexer → database
- **Impact**: Database pressure cascades to all managed clusters
- **Assessment Implication**: Cross-component failures are rarely isolated

### **Methodology vs Implementation Separation**  
- **Choice**: SKILL.md focuses on WHAT and WHY, scripts/ handle HOW
- **Benefit**: Methodology evolution independent from implementation bugs
- **Maintainability**: Script improvements don't require skill redefinition

### **Orchestration vs Specialization**
- **Design**: search-architecture coordinates, impact skills specialize
- **Pattern**: "Light glue" orchestration with deep component expertise
- **User Experience**: Single entry point with comprehensive multi-component analysis

## Data Flow and Integration

### Assessment Execution Flow
1. **Symptom Detection** (`search-architecture`) → Routes to appropriate impact skills
2. **Specialized Analysis** (Impact skills) → Generate detailed JSON reports
3. **Cross-Impact Correlation** (`search-architecture`) → Identify patterns and root causes
4. **Architectural Synthesis** → Unified insights with scaling recommendations

### JSON Integration Schema
```json
{
  "assessment_type": "search-[component]-impact",
  "confidence_score": 0.0-1.0,
  "raw_metrics": { /* component-specific metrics */ },
  "recommendations": [ /* actionable guidance */ ],
  "execution_audit": { /* transparency for debugging */ }
}
```

### Cross-Skill Communication
- **Programmatic**: JSON reports enable automated correlation
- **Manual**: Clear routing guidance between skills
- **Audit Trail**: Complete execution transparency for debugging

## Usage Patterns

### **Full System Assessment**
```bash
cd .claude/skills/search-architecture
./scripts/orchestrate-assessment.sh
```

### **Symptom-Based Analysis**  
```bash
./scripts/route-symptoms.sh api-slow
./scripts/route-symptoms.sh new-cluster
./scripts/route-symptoms.sh everything-slow
```

### **Component-Specific Deep Dive**
```bash
cd .claude/skills/search-indexer-impact
./scripts/generate-assessment.sh
```

### **Cross-Impact Analysis**
```bash
cd .claude/skills/search-architecture  
./scripts/correlate-results.sh
```

## Design Benefits

### **Proven Architecture**
- **Battle-tested**: All components working with real Prometheus integration
- **Transparent**: Complete audit trails for debugging and validation  
- **Robust**: Advanced/fallback query patterns handle missing metrics gracefully

### **Scalable Design**
- **Modular**: Each skill can be improved independently
- **Composable**: Different assessment combinations for different scenarios
- **Extensible**: Easy to add new impact skills or correlation patterns

### **User-Focused**  
- **Intelligent Routing**: Automatically determines appropriate assessments
- **Unified Interface**: Single entry point for complex multi-component analysis
- **Actionable Insights**: Focus on recommendations rather than raw data

## Supporting Infrastructure

### **Monitoring Data Structure**
```
monitoring_data/
├── impacts/           # Individual component assessment results
├── architecture/      # Orchestration and correlation results  
└── audit/            # Detailed execution logs
```

### **Prometheus Integration**
- **Advanced Queries**: PromQL with rate(), histogram_quantile(), complex aggregations
- **Fallback Patterns**: Basic queries when advanced time-series data unavailable
- **Error Handling**: Robust JSON parsing with empty response validation

### **Kubernetes Integration**
- **Multi-source Data**: Combines Prometheus metrics, kubectl, health endpoints
- **Cross-cluster Analysis**: Fleet-wide assessment capabilities
- **Resource Monitoring**: Component health, deployment status, resource utilization

This structure reflects our **actual implemented architecture** that has been tested and proven to work with real ACM Search deployments.