# Search-Agent Design Document
*Proven architecture based on working implementation*

## Actual Design Philosophy

### **Separation of Concerns + Intelligent Orchestration**

**Problem Solved**: Complex multi-component systems need both specialized expertise and coordinated analysis.

**Proven Solution**: 
- **Specialized Impact Skills**: Deep component assessment with real metrics
- **Orchestration Layer**: Intelligent coordination and architectural reasoning
- **Clean Separation**: Methodology vs Implementation in every skill

### **What We Actually Built**

1. **Start with symptoms**: "API slow", "new cluster issues", "everything broken"
2. **Route intelligently**: Orchestration determines which assessments to run  
3. **Assess with real data**: Prometheus metrics + kubectl + health endpoints
4. **Correlate and synthesize**: Cross-component pattern recognition
5. **Provide unified insights**: Architecture-aware recommendations

## Validated Architecture Pattern

### **Orchestration Layer**
**search-architecture**: The intelligent "brain" that coordinates everything
- **Routes symptoms** to appropriate impact assessments  
- **Correlates results** from multiple specialized skills
- **Provides architectural reasoning** for performance patterns
- **Synthesizes recommendations** across components

### **Impact Assessment Layer** 
**Specialized "hands" that do deep component analysis:**
- **search-api-impact**: GraphQL performance, RBAC load, client patterns
- **search-indexer-impact**: Database pressure, batch processing, request handling
- **search-collector-impact**: Cross-cluster networking, connection stress  
- **search-operator-impact**: Reconciliation, deployment health, resource consumption

### **Component Expertise Layer**
**Pure domain knowledge without monitoring implementation:**
- **search-api**: GraphQL optimization patterns, RBAC strategies
- **search-indexer**: PostgreSQL tuning, relationship computation
- **search-collector**: Networking patterns, cross-cluster optimization
- **search-operator**: Lifecycle management, deployment strategies

## Integration Strategy (Proven)

### **Primary Data Sources**
- **Prometheus monitoring**: OpenShift's built-in Prometheus for component metrics
- **Kubernetes API**: kubectl for deployment status, events, resource health
- **Health endpoints**: Direct component health and metrics endpoints
- **Log analysis**: Targeted log analysis for specific diagnostic needs

### **What We Learned About MCP**
- **MCP server integration**: Available but not primary data source for system health
- **Focus on infrastructure monitoring**: kubectl + Prometheus provide operational health
- **Component metrics over customer metrics**: Internal health drives performance assessment

## Key Architectural Decisions (Validated)

### **1. Orchestration-First Entry Point**
**Reality**: Users need guidance on what to assess
**Solution**: `search-architecture` provides intelligent routing and synthesis
**Pattern**: "Light glue" that coordinates specialists without duplicating expertise

### **2. Real Metrics Integration**  
**Reality**: Theoretical thresholds don't work; need actual Prometheus data
**Solution**: Advanced/fallback query patterns with robust error handling
**Pattern**: Always graceful degradation when monitoring data insufficient

### **3. Synchronous Pipeline Awareness**
**Discovery**: collector → indexer → database is synchronous, not async
**Impact**: Database pressure cascades to entire managed cluster fleet
**Design Response**: Cross-impact correlation essential, not optional

### **4. Separation of Concerns**
**Pattern**: SKILL.md (methodology) + scripts/ (implementation)  
**Benefit**: Methodology evolution independent from implementation bugs
**Validation**: Successfully refactored all skills without breaking domain knowledge

### **5. JSON Integration Between Skills**
**Need**: Orchestration requires programmatic access to assessment results
**Solution**: Standardized JSON reports with confidence scoring
**Pattern**: Human-readable skills + machine-readable integration

## Implementation Architecture

### **Per-Skill Structure**
```
search-component-impact/
├── SKILL.md                    # Methodology and thresholds
├── scripts/
│   ├── generate-assessment.sh  # Main orchestrator with JSON output
│   ├── prometheus-metrics.sh   # Robust metrics collection
│   ├── [analysis-type].sh      # Specialized analysis
│   └── ...
```

### **Cross-Skill Integration**
```
User Problem → search-architecture → Impact Skills → JSON Results → Correlation → Unified Insights
```

### **Data Flow**
```
Prometheus/kubectl → Impact Assessment → JSON Report → Correlation Analysis → Recommendations
```

## Proven Patterns

### **Advanced/Fallback Prometheus Queries**
```bash
# Try sophisticated time-series analysis first
if prom_query "histogram_quantile(0.95, rate(metric[5m]))"; then
    echo "✅ Advanced percentile analysis"
else  
    echo "⚠️  Fallback to basic counters"
    prom_query "metric_total / metric_count"
fi
```

### **Robust Error Handling**
```bash
# Handle empty Prometheus responses
if [ -z "$raw_response" ] || [ "$raw_response" = "" ]; then
    echo "Empty response for query: $query" 
    return 1
fi

# Validate JSON parsing
echo "$raw_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Process valid JSON
except:
    print('Query failed: Invalid JSON response')
    sys.exit(1)
"
```

### **Complete Audit Trails**
```bash
# Log every operation for debugging
echo "[$timestamp] QUERY: $query" >> "$EXECUTION_LOG"
echo "[$timestamp] RAW_RESPONSE: $raw_response" >> "$EXECUTION_LOG"
echo "[$timestamp] PARSED_STATUS: $status" >> "$EXECUTION_LOG"
```

## Validated Usage Patterns

### **Full System Assessment**
```bash
# Intelligent orchestration with automatic routing
cd .claude/skills/search-architecture
./scripts/orchestrate-assessment.sh
```
**Result**: Determines assessment strategy based on recent events and system state

### **Symptom-Based Analysis**
```bash
# Route specific symptoms to appropriate assessments  
./scripts/route-symptoms.sh api-slow
./scripts/route-symptoms.sh new-cluster  
./scripts/route-symptoms.sh everything-slow
```
**Result**: Targeted assessment strategy with architectural context

### **Cross-Impact Correlation**
```bash
# Synthesize multiple assessment results
./scripts/correlate-results.sh
```
**Result**: Pattern recognition across components with unified recommendations

### **Component Deep Dive**
```bash
# Direct specialized assessment when needed
cd .claude/skills/search-indexer-impact
./scripts/generate-assessment.sh
```
**Result**: Deep component analysis with comprehensive metrics

## Lessons Learned

### **What Actually Works**
1. **Real metrics beat theoretical thresholds**: Prometheus integration with actual data
2. **Robust error handling essential**: Advanced queries fail regularly in practice  
3. **Orchestration adds real value**: Users need guidance on what to assess
4. **Audit trails crucial**: Complex metrics collection needs debugging visibility
5. **Cross-component correlation necessary**: Synchronous pipeline means failures cascade

### **What Doesn't Work**
1. **Workflow skills without real implementation**: Too abstract to be useful
2. **Brittle Prometheus queries**: Advanced queries without fallbacks break constantly
3. **Black box assessment**: No debugging visibility when results seem wrong
4. **Isolated component analysis**: Misses root cause in cascading failure scenarios
5. **Theoretical design**: Must build working implementation to validate patterns

### **What We'd Change**
1. **Start with implementation**: Build working scripts before defining methodology
2. **Add audit trails early**: Debug visibility crucial from beginning
3. **Test with real systems**: Synthetic data doesn't reveal actual failure patterns
4. **Focus on error cases**: Prometheus infrastructure is often incomplete
5. **Validate orchestration value**: Prove coordination layer adds value over individual skills

## Future Evolution (Based on Proven Patterns)

### **Immediate Opportunities**
1. **Extend to other ACM components**: Apply impact assessment pattern to governance, app lifecycle
2. **Enhance correlation patterns**: Add more architectural failure pattern recognition
3. **Improve metric coverage**: Add more Prometheus endpoints as they become available
4. **Optimize query performance**: Tune PromQL based on real usage patterns

### **Scalable Architecture**
1. **Cross-pillar orchestration**: `acm-architecture` skill that coordinates search, governance, security
2. **Fleet-level analysis**: Scale pattern to assess entire OpenShift cluster fleets
3. **Predictive analysis**: Historical trend analysis based on proven metric collection
4. **Automated remediation**: Actions based on high-confidence assessment patterns

## Success Metrics (Actual Results)

### **Technical Validation**
- ✅ **All impact skills working**: Real Prometheus integration with fallback patterns
- ✅ **Orchestration functioning**: Intelligent routing and correlation proven  
- ✅ **Error resilience**: Graceful degradation when metrics unavailable
- ✅ **Cross-skill integration**: JSON reports enable programmatic coordination
- ✅ **Audit trail completeness**: Full debugging visibility for complex metric collection

### **Architectural Insights**
- ✅ **Synchronous pipeline understanding**: Critical design reality captured
- ✅ **Failure correlation patterns**: Database bottleneck vs component isolation
- ✅ **Prometheus query realities**: Advanced queries require sufficient data
- ✅ **Component interaction mapping**: Cross-impact relationships proven
- ✅ **Performance threshold validation**: Real thresholds based on actual metrics

---

## Conclusion

This design emerged from **building a working system** rather than theoretical planning. The orchestration + specialization pattern, robust error handling, and separation of concerns have proven effective with real ACM Search deployments.

**Key Design Principles Validated:**
- **Implementation-driven**: Build working systems first, document patterns second
- **Robust degradation**: Assume monitoring infrastructure will be incomplete  
- **Intelligent coordination**: Orchestration layer adds genuine value
- **Transparent operation**: Complete audit trails enable trust and debugging
- **Architectural awareness**: System design drives assessment strategy

This foundation provides a proven template for monitoring complex multi-component systems across domains.