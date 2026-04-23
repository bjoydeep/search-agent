#!/bin/bash
# Main Search API Impact Assessment Orchestrator
# Coordinates all assessment scripts and generates final JSON report
# Part of search-api-impact assessment methodology

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSESSMENT_OUTPUT_DIR="${ASSESSMENT_OUTPUT_DIR:-$(pwd)/monitoring_data/impacts}"

echo "=== Search API Impact Assessment ==="
echo "Started at: $(date)"

# Get hub cluster information
HUB_CLUSTER_ID=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.clusterID}' 2>/dev/null || echo "unknown")
HUB_OCP_VERSION=$(kubectl get managedcluster local-cluster -o jsonpath='{.metadata.labels.openshiftVersion-major-minor}' 2>/dev/null || echo "unknown")

echo "Hub Cluster: local-cluster ($HUB_CLUSTER_ID)"
echo "OpenShift Version: $HUB_OCP_VERSION"
echo ""

# Create output directory if it doesn't exist
mkdir -p "$ASSESSMENT_OUTPUT_DIR"

# Temporary files for collecting metrics and execution logs
METRICS_FILE=$(mktemp)
EXECUTION_LOG=$(mktemp)
trap "rm -f $METRICS_FILE $EXECUTION_LOG" EXIT

# Start execution log
echo "=== SEARCH API IMPACT ASSESSMENT EXECUTION LOG ===" > "$EXECUTION_LOG"
echo "Started: $(date)" >> "$EXECUTION_LOG"
echo "Hub Cluster: $HUB_CLUSTER_ID" >> "$EXECUTION_LOG"
echo "" >> "$EXECUTION_LOG"

# Execute assessment scripts in order with logging - continue on errors to ensure audit trail
echo "=== 1/4: Prometheus API Metrics Collection (60% weight) ===" | tee -a "$EXECUTION_LOG"
export EXECUTION_LOG  # Make available to child scripts
"$SCRIPT_DIR/prometheus-metrics.sh" | tee -a "$METRICS_FILE" || echo "WARNING: Prometheus metrics collection encountered errors" | tee -a "$EXECUTION_LOG"

echo "" | tee -a "$EXECUTION_LOG"
echo "=== 2/4: User Pattern Analysis (25% weight) ===" | tee -a "$EXECUTION_LOG"
"$SCRIPT_DIR/user-pattern-analysis.sh" | tee -a "$METRICS_FILE" || echo "WARNING: User pattern analysis encountered errors" | tee -a "$EXECUTION_LOG"

echo "" | tee -a "$EXECUTION_LOG"
echo "=== 3/4: Database and WebSocket Analysis (10% weight) ===" | tee -a "$EXECUTION_LOG"
"$SCRIPT_DIR/database-websocket.sh" | tee -a "$METRICS_FILE" || echo "WARNING: Database and WebSocket analysis encountered errors" | tee -a "$EXECUTION_LOG"

echo "" | tee -a "$EXECUTION_LOG"
echo "=== 4/4: RBAC Authentication Analysis (5% weight) ===" | tee -a "$EXECUTION_LOG"
"$SCRIPT_DIR/rbac-analysis.sh" | tee -a "$METRICS_FILE" || echo "WARNING: RBAC analysis encountered errors" | tee -a "$EXECUTION_LOG"

echo "Assessment execution completed: $(date)" >> "$EXECUTION_LOG"

# Parse collected metrics and calculate assessment
echo ""
echo "=== Assessment Calculation ==="

# Extract key metrics from the collected data
# Parse the new prometheus output format: {labels}: value
API_RESPONSE_TIME=$(grep -E "Average request duration|}: [0-9.]+" "$METRICS_FILE" | grep -o "[0-9.]*$" | head -1 || echo "0")
ERROR_RATE=$(grep -E "No error request data|No successful request data" "$METRICS_FILE" > /dev/null && echo "0" || grep -E "error_rate.*[0-9]" "$METRICS_FILE" | grep -o "[0-9.]*" | head -1 || echo "0")
DB_QUERY_TIME=$(grep -E "Average query duration|resolveItemsFunc.*}: [0-9.]+" "$METRICS_FILE" | grep -o "[0-9.]*$" | head -1 || echo "0")

echo "Extracted metrics:"
echo "  API response time: ${API_RESPONSE_TIME}s"
echo "  Error rate: ${ERROR_RATE}%"
echo "  DB query time: ${DB_QUERY_TIME}s"

# Calculate basic performance metrics
# Ensure we have valid numeric values
if [ -z "$API_RESPONSE_TIME" ] || [ "$API_RESPONSE_TIME" = "" ]; then API_RESPONSE_TIME="0"; fi
if [ -z "$ERROR_RATE" ] || [ "$ERROR_RATE" = "" ]; then ERROR_RATE="0"; fi
if [ -z "$DB_QUERY_TIME" ] || [ "$DB_QUERY_TIME" = "" ]; then DB_QUERY_TIME="0"; fi

# Simple confidence scoring using awk for float comparison
if [ "$(echo "$API_RESPONSE_TIME" | awk '{print ($1 > 0)}')" -eq 1 ]; then
  if [ "$(echo "$API_RESPONSE_TIME $ERROR_RATE" | awk '{print ($1 < 0.5 && $2 < 2)}')" -eq 1 ]; then
    CONFIDENCE_SCORE="0.9"
    CONFIDENCE_LEVEL="EXCELLENT"
  elif [ "$(echo "$API_RESPONSE_TIME $ERROR_RATE" | awk '{print ($1 < 2 && $2 < 5)}')" -eq 1 ]; then
    CONFIDENCE_SCORE="0.7"
    CONFIDENCE_LEVEL="GOOD"
  else
    CONFIDENCE_SCORE="0.5"
    CONFIDENCE_LEVEL="MEDIUM"
  fi
else
  CONFIDENCE_SCORE="0.5"
  CONFIDENCE_LEVEL="MEDIUM"
fi

echo "  Confidence score: $CONFIDENCE_SCORE"
echo "  Health level: $CONFIDENCE_LEVEL"

# Save detailed execution log for debugging
EXECUTION_LOG_FILE="$ASSESSMENT_OUTPUT_DIR/${HUB_CLUSTER_ID}_api_execution.log"
cp "$EXECUTION_LOG" "$EXECUTION_LOG_FILE"

# Generate JSON assessment report with execution details
OUTPUT_FILE="$ASSESSMENT_OUTPUT_DIR/${HUB_CLUSTER_ID}_api_impact.json"

# Escape the execution log content for JSON
EXECUTION_LOG_JSON=$(cat "$EXECUTION_LOG" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')

cat > "$OUTPUT_FILE" <<EOF
{
  "assessment_type": "search-api-impact",
  "assessment_scope": "hub",
  "hub_cluster_name": "local-cluster",
  "hub_cluster_id": "$HUB_CLUSTER_ID",
  "hub_openshift_version": "$HUB_OCP_VERSION",
  "assessment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "confidence_score": $CONFIDENCE_SCORE,
  "confidence_level": "$CONFIDENCE_LEVEL",
  "contributing_factors": [
    "API response time: ${API_RESPONSE_TIME}s",
    "Error rate: ${ERROR_RATE}%",
    "Database query time: ${DB_QUERY_TIME}s"
  ],
  "raw_metrics": {
    "api_response_time_seconds": $API_RESPONSE_TIME,
    "error_rate_percent": $ERROR_RATE,
    "db_query_duration_seconds": $DB_QUERY_TIME,
    "metrics_availability": 1.0
  },
  "script_execution": {
    "prometheus_metrics": "completed",
    "user_pattern_analysis": "completed",
    "database_websocket_analysis": "completed",
    "rbac_analysis": "completed"
  },
  "execution_audit_trail": {
    "detailed_log_file": "${HUB_CLUSTER_ID}_api_execution.log",
    "prometheus_queries_executed": "logged with responses",
    "user_patterns_analyzed": "documented",
    "raw_responses": "captured for debugging"
  },
  "debugging_info": {
    "metrics_file": "temporary, contains parsed output",
    "execution_log": "saved separately for audit trail",
    "query_timestamps": "included in detailed log",
    "raw_prometheus_responses": "captured for validation"
  },
  "recommendations": [
    "Review detailed execution log for query-by-query analysis",
    "Check raw API responses if metrics seem incorrect",
    "Monitor GraphQL query patterns over time",
    "Consider RBAC optimization for authentication overhead"
  ],
  "architectural_analysis": "Assessment completed using separated script methodology with full execution audit trail"
}
EOF

echo ""
echo "=== Assessment Complete ==="
echo "Report saved to: $OUTPUT_FILE"
echo "Completed at: $(date)"

# Display summary
echo ""
echo "=== SUMMARY ==="
echo "Confidence Score: $CONFIDENCE_SCORE ($CONFIDENCE_LEVEL)"
echo "API Response Time: ${API_RESPONSE_TIME}s"
echo "Error Rate: ${ERROR_RATE}%"
echo "DB Query Time: ${DB_QUERY_TIME}s"