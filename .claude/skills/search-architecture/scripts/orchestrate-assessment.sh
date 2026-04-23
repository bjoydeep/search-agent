#!/bin/bash
# Search Architecture Assessment Orchestrator
# Intelligently routes symptoms to appropriate impact assessments
# Coordinates cross-component analysis and synthesis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHITECTURE_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$(dirname "$ARCHITECTURE_DIR")"
OUTPUT_DIR="${ASSESSMENT_OUTPUT_DIR:-$(pwd)/monitoring_data/architecture}"

echo "=== Search Architecture Assessment Orchestrator ==="
echo "Started at: $(date)"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get hub cluster information
HUB_CLUSTER_ID=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.clusterID}' 2>/dev/null || echo "unknown")
HUB_OCP_VERSION=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.openshiftVersion-major-minor}' 2>/dev/null || echo "unknown")

echo "Hub Cluster: local-cluster ($HUB_CLUSTER_ID)"
echo "OpenShift Version: $HUB_OCP_VERSION"
echo ""

# Assessment execution log
EXECUTION_LOG=$(mktemp)
trap "rm -f $EXECUTION_LOG" EXIT

echo "=== ARCHITECTURE ORCHESTRATOR EXECUTION LOG ===" > "$EXECUTION_LOG"
echo "Started: $(date)" >> "$EXECUTION_LOG"
echo "Hub Cluster: $HUB_CLUSTER_ID" >> "$EXECUTION_LOG"
echo "" >> "$EXECUTION_LOG"

# Function to run impact assessment with error handling
run_impact_assessment() {
    local skill_name="$1"
    local assessment_script="$2"
    local timestamp=$(date '+%H:%M:%S')

    echo "[$timestamp] ORCHESTRATOR: Starting $skill_name assessment" | tee -a "$EXECUTION_LOG"

    if [ -f "$assessment_script" ]; then
        echo "=== $skill_name Assessment ===" | tee -a "$EXECUTION_LOG"
        export EXECUTION_LOG  # Make available to child scripts

        # Run the assessment with timeout and error capture
        if timeout 300 "$assessment_script" 2>&1 | tee -a "$EXECUTION_LOG"; then
            echo "[$timestamp] ORCHESTRATOR: $skill_name assessment completed successfully" >> "$EXECUTION_LOG"
            return 0
        else
            echo "[$timestamp] ORCHESTRATOR: $skill_name assessment failed or timed out" >> "$EXECUTION_LOG"
            return 1
        fi
    else
        echo "[$timestamp] ORCHESTRATOR: $skill_name assessment script not found: $assessment_script" >> "$EXECUTION_LOG"
        return 1
    fi
}

# Detect system symptoms and route to appropriate assessments
echo "=== Symptom Detection and Routing ==="

# Check for recent events that indicate what to assess
RECENT_CLUSTER_EVENTS=$(kubectl get events --sort-by='.lastTimestamp' -o json 2>/dev/null | jq -r '.items[0:10][] | select(.source.component=="cluster-manager" or .involvedObject.kind=="ManagedCluster") | .message' 2>/dev/null || echo "")

RECENT_SEARCH_EVENTS=$(kubectl get events --sort-by='.lastTimestamp' -o json 2>/dev/null | jq -r '.items[0:10][] | select(.involvedObject.name | test("search")) | .message' 2>/dev/null || echo "")

# Basic component health check to determine assessment scope
SEARCH_PODS_STATUS=$(kubectl get pods -l "app in (search-api,search-indexer,postgres)" -A --no-headers 2>/dev/null || echo "")
SEARCH_OPERATOR_STATUS=$(kubectl get pods -l "control-plane=search-controller-manager" -A --no-headers 2>/dev/null || echo "")

echo "Recent cluster events: $(echo "$RECENT_CLUSTER_EVENTS" | head -2 | tr '\n' '; ' || echo "none")"
echo "Recent search events: $(echo "$RECENT_SEARCH_EVENTS" | head -2 | tr '\n' '; ' || echo "none")"
echo "Search components status: $(echo "$SEARCH_PODS_STATUS" | wc -l) pods found"
echo ""

# Determine assessment strategy based on symptoms
ASSESSMENT_STRATEGY="comprehensive"  # Default to full assessment

# Check if this looks like a specific component issue
if echo "$RECENT_SEARCH_EVENTS" | grep -qi "api\|graphql"; then
    ASSESSMENT_STRATEGY="api-focused"
elif echo "$RECENT_SEARCH_EVENTS" | grep -qi "indexer\|database\|postgres"; then
    ASSESSMENT_STRATEGY="indexer-focused"
elif echo "$RECENT_CLUSTER_EVENTS" | grep -qi "managedcluster"; then
    ASSESSMENT_STRATEGY="collector-focused"
elif echo "$RECENT_SEARCH_EVENTS" | grep -qi "operator\|deployment\|addon"; then
    ASSESSMENT_STRATEGY="operator-focused"
fi

echo "Assessment strategy: $ASSESSMENT_STRATEGY"
echo "$(date '+%H:%M:%S') ASSESSMENT_STRATEGY: $ASSESSMENT_STRATEGY" >> "$EXECUTION_LOG"
echo ""

# Execute assessments based on strategy
case "$ASSESSMENT_STRATEGY" in
    "api-focused")
        echo "=== API-Focused Assessment (API + Indexer) ==="
        run_impact_assessment "search-api-impact" "$SKILLS_DIR/search-api-impact/scripts/generate-assessment.sh"
        run_impact_assessment "search-indexer-impact" "$SKILLS_DIR/search-indexer-impact/scripts/generate-assessment.sh"
        ;;
    "indexer-focused")
        echo "=== Indexer-Focused Assessment (Indexer + Operator) ==="
        run_impact_assessment "search-indexer-impact" "$SKILLS_DIR/search-indexer-impact/scripts/generate-assessment.sh"
        run_impact_assessment "search-operator-impact" "$SKILLS_DIR/search-operator-impact/scripts/generate-assessment.sh"
        ;;
    "collector-focused")
        echo "=== Collector-Focused Assessment (Collector + Indexer) ==="
        run_impact_assessment "search-collector-impact" "$SKILLS_DIR/search-collector-impact/scripts/generate-assessment.sh"
        run_impact_assessment "search-indexer-impact" "$SKILLS_DIR/search-indexer-impact/scripts/generate-assessment.sh"
        ;;
    "operator-focused")
        echo "=== Operator-Focused Assessment (Operator + All Components) ==="
        run_impact_assessment "search-operator-impact" "$SKILLS_DIR/search-operator-impact/scripts/generate-assessment.sh"
        run_impact_assessment "search-indexer-impact" "$SKILLS_DIR/search-indexer-impact/scripts/generate-assessment.sh"
        run_impact_assessment "search-api-impact" "$SKILLS_DIR/search-api-impact/scripts/generate-assessment.sh"
        ;;
    "comprehensive"|*)
        echo "=== Comprehensive Assessment (All Components) ==="
        run_impact_assessment "search-api-impact" "$SKILLS_DIR/search-api-impact/scripts/generate-assessment.sh"
        run_impact_assessment "search-indexer-impact" "$SKILLS_DIR/search-indexer-impact/scripts/generate-assessment.sh"
        run_impact_assessment "search-collector-impact" "$SKILLS_DIR/search-collector-impact/scripts/generate-assessment.sh"
        run_impact_assessment "search-operator-impact" "$SKILLS_DIR/search-operator-impact/scripts/generate-assessment.sh"
        ;;
esac

echo ""
echo "=== Assessment Orchestration Complete ==="

# Save detailed execution log
EXECUTION_LOG_FILE="$OUTPUT_DIR/${HUB_CLUSTER_ID}_architecture_orchestration.log"
cp "$EXECUTION_LOG" "$EXECUTION_LOG_FILE"

echo "Orchestration log saved to: $EXECUTION_LOG_FILE"
echo "Individual assessment results in: monitoring_data/impacts/"

# Generate orchestration summary
ORCHESTRATION_SUMMARY="$OUTPUT_DIR/${HUB_CLUSTER_ID}_architecture_summary.json"

# Count successful assessments by checking for output files
API_RESULT_EXISTS=$( [ -f "monitoring_data/impacts/${HUB_CLUSTER_ID}_api_impact.json" ] && echo "true" || echo "false" )
INDEXER_RESULT_EXISTS=$( [ -f "monitoring_data/impacts/${HUB_CLUSTER_ID}_indexer_impact.json" ] && echo "true" || echo "false" )
COLLECTOR_RESULT_EXISTS=$( [ -f "monitoring_data/impacts/${HUB_CLUSTER_ID}_collector_impact.json" ] && echo "true" || echo "false" )
OPERATOR_RESULT_EXISTS=$( [ -f "monitoring_data/impacts/${HUB_CLUSTER_ID}_operator_impact.json" ] && echo "true" || echo "false" )

cat > "$ORCHESTRATION_SUMMARY" <<EOF
{
  "orchestration_type": "search-architecture-assessment",
  "orchestration_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hub_cluster_id": "$HUB_CLUSTER_ID",
  "assessment_strategy": "$ASSESSMENT_STRATEGY",
  "assessments_completed": {
    "search_api_impact": $API_RESULT_EXISTS,
    "search_indexer_impact": $INDEXER_RESULT_EXISTS,
    "search_collector_impact": $COLLECTOR_RESULT_EXISTS,
    "search_operator_impact": $OPERATOR_RESULT_EXISTS
  },
  "next_steps": [
    "Run correlation analysis: scripts/correlate-results.sh",
    "Review individual assessment results in monitoring_data/impacts/",
    "Check orchestration log for detailed execution trace"
  ],
  "execution_audit": {
    "orchestration_log": "${HUB_CLUSTER_ID}_architecture_orchestration.log",
    "strategy_reasoning": "Based on recent events and component status",
    "timeout_used": "300 seconds per assessment",
    "error_handling": "Individual assessment failures logged but do not stop orchestration"
  }
}
EOF

echo ""
echo "=== Orchestration Summary ==="
echo "Strategy used: $ASSESSMENT_STRATEGY"
echo "Summary saved to: $ORCHESTRATION_SUMMARY"
echo ""
echo "Next: Run correlation analysis with scripts/correlate-results.sh"
echo "Completed at: $(date)"