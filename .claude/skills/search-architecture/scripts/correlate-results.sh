#!/bin/bash
# Search Architecture Results Correlation and Synthesis
# Analyzes cross-impact relationships and provides architectural insights
# Synthesizes individual component assessments into unified system health picture

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPACTS_DIR="${IMPACTS_DIR:-$(pwd)/monitoring_data/impacts}"
OUTPUT_DIR="${ASSESSMENT_OUTPUT_DIR:-$(pwd)/monitoring_data/architecture}"

echo "=== Search Architecture Correlation Analysis ==="
echo "Started at: $(date)"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get hub cluster information
HUB_CLUSTER_ID=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.clusterID}' 2>/dev/null || echo "unknown")

echo "Hub Cluster: $HUB_CLUSTER_ID"
echo "Analyzing impact results from: $IMPACTS_DIR"
echo ""

# Check for available assessment results
API_RESULT="${IMPACTS_DIR}/${HUB_CLUSTER_ID}_api_impact.json"
INDEXER_RESULT="${IMPACTS_DIR}/${HUB_CLUSTER_ID}_indexer_impact.json"
COLLECTOR_RESULT="${IMPACTS_DIR}/${HUB_CLUSTER_ID}_collector_impact.json"
OPERATOR_RESULT="${IMPACTS_DIR}/${HUB_CLUSTER_ID}_operator_impact.json"

echo "=== Available Assessment Results ==="
[ -f "$API_RESULT" ] && echo "✅ API impact assessment found" || echo "❌ API impact assessment missing"
[ -f "$INDEXER_RESULT" ] && echo "✅ Indexer impact assessment found" || echo "❌ Indexer impact assessment missing"
[ -f "$COLLECTOR_RESULT" ] && echo "✅ Collector impact assessment found" || echo "❌ Collector impact assessment missing"
[ -f "$OPERATOR_RESULT" ] && echo "✅ Operator impact assessment found" || echo "❌ Operator impact assessment missing"
echo ""

# Function to safely extract JSON value
extract_json_value() {
    local file="$1"
    local path="$2"
    local default="$3"

    if [ -f "$file" ]; then
        jq -r "$path // \"$default\"" "$file" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

# Function to safely extract numeric JSON value
extract_json_number() {
    local file="$1"
    local path="$2"
    local default="$3"

    if [ -f "$file" ]; then
        jq -r "$path // $default" "$file" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

# Extract key metrics from each assessment
echo "=== Extracting Component Metrics ==="

# API metrics
API_CONFIDENCE=$(extract_json_number "$API_RESULT" ".confidence_score" "0.5")
API_LEVEL=$(extract_json_value "$API_RESULT" ".confidence_level" "UNKNOWN")
API_TIMESTAMP=$(extract_json_value "$API_RESULT" ".assessment_timestamp" "unknown")

echo "API Assessment: Confidence $API_CONFIDENCE ($API_LEVEL) at $API_TIMESTAMP"

# Indexer metrics
INDEXER_CONFIDENCE=$(extract_json_number "$INDEXER_RESULT" ".confidence_score" "0.5")
INDEXER_LEVEL=$(extract_json_value "$INDEXER_RESULT" ".confidence_level" "UNKNOWN")
INDEXER_TIMESTAMP=$(extract_json_value "$INDEXER_RESULT" ".assessment_timestamp" "unknown")
INDEXER_REQUESTS=$(extract_json_number "$INDEXER_RESULT" ".raw_metrics.total_requests_processed" "0")

echo "Indexer Assessment: Confidence $INDEXER_CONFIDENCE ($INDEXER_LEVEL) at $INDEXER_TIMESTAMP"
echo "  └─ Requests processed: $INDEXER_REQUESTS"

# Collector metrics
COLLECTOR_CONFIDENCE=$(extract_json_number "$COLLECTOR_RESULT" ".confidence_score" "0.5")
COLLECTOR_LEVEL=$(extract_json_value "$COLLECTOR_RESULT" ".confidence_level" "UNKNOWN")
COLLECTOR_TIMESTAMP=$(extract_json_value "$COLLECTOR_RESULT" ".assessment_timestamp" "unknown")

echo "Collector Assessment: Confidence $COLLECTOR_CONFIDENCE ($COLLECTOR_LEVEL) at $COLLECTOR_TIMESTAMP"

# Operator metrics
OPERATOR_CONFIDENCE=$(extract_json_number "$OPERATOR_RESULT" ".confidence_score" "0.5")
OPERATOR_LEVEL=$(extract_json_value "$OPERATOR_RESULT" ".confidence_level" "UNKNOWN")
OPERATOR_TIMESTAMP=$(extract_json_value "$OPERATOR_RESULT" ".assessment_timestamp" "unknown")

echo "Operator Assessment: Confidence $OPERATOR_CONFIDENCE ($OPERATOR_LEVEL) at $OPERATOR_TIMESTAMP"
echo ""

# Cross-component correlation analysis
echo "=== Cross-Component Correlation Analysis ==="

# Calculate overall system confidence (weighted average)
# Weights: Indexer 40%, API 30%, Operator 20%, Collector 10% (based on criticality)
SYSTEM_CONFIDENCE=$(echo "scale=3; ($INDEXER_CONFIDENCE * 0.4) + ($API_CONFIDENCE * 0.3) + ($OPERATOR_CONFIDENCE * 0.2) + ($COLLECTOR_CONFIDENCE * 0.1)" | bc)

echo "System-wide confidence score: $SYSTEM_CONFIDENCE"

# Determine overall system health level
SYSTEM_LEVEL="UNKNOWN"
if (( $(echo "$SYSTEM_CONFIDENCE >= 0.9" | bc -l) )); then
    SYSTEM_LEVEL="EXCELLENT"
elif (( $(echo "$SYSTEM_CONFIDENCE >= 0.7" | bc -l) )); then
    SYSTEM_LEVEL="GOOD"
elif (( $(echo "$SYSTEM_CONFIDENCE >= 0.4" | bc -l) )); then
    SYSTEM_LEVEL="MEDIUM"
elif (( $(echo "$SYSTEM_CONFIDENCE >= 0.2" | bc -l) )); then
    SYSTEM_LEVEL="LOW"
else
    SYSTEM_LEVEL="CRITICAL"
fi

echo "Overall system health: $SYSTEM_LEVEL"
echo ""

# Identify correlation patterns and architectural insights
echo "=== Architectural Pattern Analysis ==="

# Pattern 1: Database bottleneck (Indexer stress + API slowness)
if (( $(echo "$INDEXER_CONFIDENCE < 0.6" | bc -l) )) && (( $(echo "$API_CONFIDENCE < 0.6" | bc -l) )); then
    echo "🔍 PATTERN DETECTED: Database Bottleneck"
    echo "  └─ Both indexer and API showing stress - likely PostgreSQL pressure"
    echo "  └─ Recommendation: Scale database resources, optimize queries"
    PATTERN_DATABASE_BOTTLENECK="true"
else
    PATTERN_DATABASE_BOTTLENECK="false"
fi

# Pattern 2: Cascading failure (Collector stress → Indexer overload → API delays)
if (( $(echo "$COLLECTOR_CONFIDENCE < 0.6" | bc -l) )) && (( $(echo "$INDEXER_CONFIDENCE < 0.7" | bc -l) )); then
    echo "🔍 PATTERN DETECTED: Cascading Collection Stress"
    echo "  └─ Collector issues feeding into indexer overload"
    echo "  └─ Recommendation: Address collector networking, consider throttling"
    PATTERN_CASCADING_STRESS="true"
else
    PATTERN_CASCADING_STRESS="false"
fi

# Pattern 3: Operator instability affecting all components
if (( $(echo "$OPERATOR_CONFIDENCE < 0.6" | bc -l) )) && (( $(echo "$SYSTEM_CONFIDENCE < 0.7" | bc -l) )); then
    echo "🔍 PATTERN DETECTED: Operator-Driven Instability"
    echo "  └─ Operator issues correlating with system-wide problems"
    echo "  └─ Recommendation: Focus on operator stability, check resource limits"
    PATTERN_OPERATOR_INSTABILITY="true"
else
    PATTERN_OPERATOR_INSTABILITY="false"
fi

# Pattern 4: Isolated component issue
ISOLATED_ISSUES=""
if (( $(echo "$API_CONFIDENCE < 0.6" | bc -l) )) && (( $(echo "$INDEXER_CONFIDENCE > 0.7" | bc -l) )); then
    ISOLATED_ISSUES="API-specific (RBAC/GraphQL optimization needed)"
elif (( $(echo "$INDEXER_CONFIDENCE < 0.6" | bc -l) )) && (( $(echo "$API_CONFIDENCE > 0.7" | bc -l) )); then
    ISOLATED_ISSUES="Indexer-specific (database tuning needed)"
elif (( $(echo "$COLLECTOR_CONFIDENCE < 0.6" | bc -l) )) && (( $(echo "$INDEXER_CONFIDENCE > 0.7" | bc -l) )); then
    ISOLATED_ISSUES="Collector-specific (networking optimization needed)"
fi

if [ ! -z "$ISOLATED_ISSUES" ]; then
    echo "🔍 PATTERN DETECTED: Isolated Component Issue"
    echo "  └─ Issue appears contained to: $ISOLATED_ISSUES"
    echo "  └─ Recommendation: Focus remediation on specific component"
fi
echo ""

# Generate architectural recommendations
echo "=== Architectural Recommendations ==="

RECOMMENDATIONS=""

if [ "$PATTERN_DATABASE_BOTTLENECK" = "true" ]; then
    RECOMMENDATIONS="$RECOMMENDATIONS\"Scale PostgreSQL resources (CPU, memory, connections)\", \"Optimize indexer batch sizes\", \"Consider read replicas for API queries\", "
fi

if [ "$PATTERN_CASCADING_STRESS" = "true" ]; then
    RECOMMENDATIONS="$RECOMMENDATIONS\"Implement collector request throttling\", \"Check cross-cluster network latency\", \"Scale indexer horizontally\", "
fi

if [ "$PATTERN_OPERATOR_INSTABILITY" = "true" ]; then
    RECOMMENDATIONS="$RECOMMENDATIONS\"Increase operator resource limits\", \"Check leader election stability\", \"Verify addon deployment health\", "
fi

if [ ! -z "$ISOLATED_ISSUES" ]; then
    if echo "$ISOLATED_ISSUES" | grep -q "API"; then
        RECOMMENDATIONS="$RECOMMENDATIONS\"Optimize GraphQL query complexity\", \"Reduce RBAC evaluation overhead\", \"Scale API horizontally\", "
    elif echo "$ISOLATED_ISSUES" | grep -q "Indexer"; then
        RECOMMENDATIONS="$RECOMMENDATIONS\"Tune PostgreSQL query performance\", \"Optimize relationship computation\", \"Increase indexer resources\", "
    elif echo "$ISOLATED_ISSUES" | grep -q "Collector"; then
        RECOMMENDATIONS="$RECOMMENDATIONS\"Optimize collector networking\", \"Check cross-cluster connectivity\", \"Scale collector fleet\", "
    fi
fi

# Remove trailing comma and wrap in array
RECOMMENDATIONS="[${RECOMMENDATIONS%*, }]"

# Generate comprehensive correlation report
CORRELATION_REPORT="$OUTPUT_DIR/${HUB_CLUSTER_ID}_architecture_correlation.json"

cat > "$CORRELATION_REPORT" <<EOF
{
  "correlation_type": "search-architecture-correlation",
  "correlation_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hub_cluster_id": "$HUB_CLUSTER_ID",
  "overall_system_health": {
    "confidence_score": $SYSTEM_CONFIDENCE,
    "confidence_level": "$SYSTEM_LEVEL",
    "component_breakdown": {
      "api_confidence": $API_CONFIDENCE,
      "indexer_confidence": $INDEXER_CONFIDENCE,
      "collector_confidence": $COLLECTOR_CONFIDENCE,
      "operator_confidence": $OPERATOR_CONFIDENCE
    },
    "weighting_strategy": "Indexer 40%, API 30%, Operator 20%, Collector 10%"
  },
  "architectural_patterns": {
    "database_bottleneck": $PATTERN_DATABASE_BOTTLENECK,
    "cascading_stress": $PATTERN_CASCADING_STRESS,
    "operator_instability": $PATTERN_OPERATOR_INSTABILITY,
    "isolated_issues": "$ISOLATED_ISSUES"
  },
  "cross_component_analysis": {
    "data_flow_health": "Collector → Indexer → API chain analyzed",
    "failure_correlation": "Cross-component failure patterns identified",
    "bottleneck_identification": "Central vs distributed bottlenecks assessed"
  },
  "recommendations": $RECOMMENDATIONS,
  "source_assessments": {
    "api_assessment_time": "$API_TIMESTAMP",
    "indexer_assessment_time": "$INDEXER_TIMESTAMP",
    "collector_assessment_time": "$COLLECTOR_TIMESTAMP",
    "operator_assessment_time": "$OPERATOR_TIMESTAMP"
  },
  "architectural_insights": {
    "primary_risk_factors": "Based on confidence score breakdown and pattern analysis",
    "impact_chain_analysis": "Collector stress → Indexer load → Database pressure → API latency",
    "scaling_recommendations": "Component-specific vs system-wide scaling needs identified"
  }
}
EOF

echo "System Health: $SYSTEM_LEVEL (confidence: $SYSTEM_CONFIDENCE)"
echo "Patterns identified: Database bottleneck: $PATTERN_DATABASE_BOTTLENECK, Cascading stress: $PATTERN_CASCADING_STRESS"
echo ""
echo "Correlation report saved to: $CORRELATION_REPORT"
echo "Completed at: $(date)"