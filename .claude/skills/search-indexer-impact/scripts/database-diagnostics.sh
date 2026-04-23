#!/bin/bash
# Comprehensive PostgreSQL Diagnostics for Search Indexer
# Weight: 10% of overall assessment
# Part of search-indexer-impact assessment methodology
# Based on postgres-debug.sh patterns from ACM Search

set -euo pipefail

echo "=== Comprehensive PostgreSQL Diagnostics ==="

# Robust PostgreSQL Pod Discovery with Multiple Fallback Strategies
echo "=== PostgreSQL Pod Discovery ==="

# Strategy 1: Try common ACM search labels
POSTGRES_POD=$(kubectl get pods -l app=postgres -A --no-headers -o custom-columns=:metadata.name 2>/dev/null | head -1)
POSTGRES_NS=$(kubectl get pods -l app=postgres -A --no-headers -o custom-columns=:metadata.namespace 2>/dev/null | head -1)

if [ -z "$POSTGRES_POD" ]; then
  echo "Strategy 1 (app=postgres) failed, trying strategy 2..."
  # Strategy 2: Try component label
  POSTGRES_POD=$(kubectl get pods -l component=postgres -A --no-headers -o custom-columns=:metadata.name 2>/dev/null | head -1)
  POSTGRES_NS=$(kubectl get pods -l component=postgres -A --no-headers -o custom-columns=:metadata.namespace 2>/dev/null | head -1)
fi

if [ -z "$POSTGRES_POD" ]; then
  echo "Strategy 2 (component=postgres) failed, trying strategy 3..."
  # Strategy 3: Try original label but corrected
  POSTGRES_POD=$(kubectl get pods -l name=search-postgres -A --no-headers -o custom-columns=:metadata.name 2>/dev/null | head -1)
  POSTGRES_NS=$(kubectl get pods -l name=search-postgres -A --no-headers -o custom-columns=:metadata.namespace 2>/dev/null | head -1)
fi

if [ -z "$POSTGRES_POD" ]; then
  echo "Strategy 3 (name=search-postgres) failed, trying strategy 4..."
  # Strategy 4: Pattern-based discovery in common ACM namespace
  ACM_NAMESPACE=$(kubectl get multiclusterhub -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace 2>/dev/null | head -1 || echo "open-cluster-management")
  POSTGRES_POD=$(kubectl get pods -n "$ACM_NAMESPACE" 2>/dev/null | grep postgres | awk '{print $1}' | head -1)
  POSTGRES_NS="$ACM_NAMESPACE"
fi

if [ -z "$POSTGRES_POD" ]; then
  echo "Strategy 4 (pattern-based) failed, trying strategy 5..."
  # Strategy 5: Global pattern search
  POSTGRES_POD=$(kubectl get pods -A 2>/dev/null | grep postgres | awk '{print $2}' | head -1)
  POSTGRES_NS=$(kubectl get pods -A 2>/dev/null | grep postgres | awk '{print $1}' | head -1)
fi

# Log discovery results
if [ ! -z "$POSTGRES_POD" ]; then
  echo "✅ PostgreSQL pod found: $POSTGRES_POD in namespace: $POSTGRES_NS"
  echo "$(date '+%H:%M:%S') POSTGRES_DISCOVERY: SUCCESS - pod=$POSTGRES_POD, namespace=$POSTGRES_NS" >> "${EXECUTION_LOG:-/dev/null}"
else
  echo "❌ PostgreSQL pod not found after all discovery strategies"
  echo "$(date '+%H:%M:%S') POSTGRES_DISCOVERY: FAILED - no PostgreSQL pod found" >> "${EXECUTION_LOG:-/dev/null}"
fi

# Detect database user from environment or default
DB_USER=$(kubectl get secret search-postgres -n $POSTGRES_NS -o jsonpath='{.data.database-user}' 2>/dev/null | base64 -d 2>/dev/null || echo "searchuser")
DB_NAME=$(kubectl get secret search-postgres -n $POSTGRES_NS -o jsonpath='{.data.database-name}' 2>/dev/null | base64 -d 2>/dev/null || echo "search")

# Helper function for PostgreSQL queries with execution logging
db_query() {
  local query="$1"
  local description="$2"
  local timestamp=$(date '+%H:%M:%S')

  # Log the query attempt
  echo "[$timestamp] DB_QUERY: $description" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] SQL: $query" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute the query and capture both output and raw response
  local raw_output=$(kubectl exec -n $POSTGRES_NS $POSTGRES_POD -- psql -d $DB_NAME -U $DB_USER -c "$query" 2>&1)
  local exit_code=$?

  # Log raw response for debugging
  echo "[$timestamp] RAW_OUTPUT: $raw_output" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"

  # Display results and log status
  if [ $exit_code -eq 0 ]; then
    echo "[$timestamp] DB_STATUS: success" >> "${EXECUTION_LOG:-/dev/null}"
    echo "$raw_output"
  else
    echo "[$timestamp] DB_ERROR: Query failed with exit code $exit_code" >> "${EXECUTION_LOG:-/dev/null}"
    echo "ERROR: $description failed"
    echo "$raw_output"
  fi

  echo "[$timestamp] DB_QUERY_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"
}

if [ ! -z "$POSTGRES_POD" ]; then
  echo "Starting PostgreSQL diagnostic collection at $(date)"
  echo "Using database: $DB_NAME, user: $DB_USER"

  # Log database connection details
  echo "$(date '+%H:%M:%S') DATABASE_CONNECTION: pod=$POSTGRES_POD, namespace=$POSTGRES_NS, db=$DB_NAME, user=$DB_USER" >> "${EXECUTION_LOG:-/dev/null}"

  # === RESOURCE STATISTICS ===
  echo ""
  echo "=== RESOURCE STATISTICS ==="

  # Total resources and clusters
  echo "Total resources and clusters:"
  db_query "SELECT COUNT(*) as total_resources, COUNT(DISTINCT cluster) as total_clusters FROM search.resources;" "Total resources and clusters count"

  # Resources by cluster (top 20)
  echo ""
  echo "Resources by cluster (top 20):"
  db_query "SELECT cluster, COUNT(*) as resource_count, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage FROM search.resources GROUP BY cluster ORDER BY COUNT(*) DESC LIMIT 20;" "Resources by cluster distribution"

  # Resources by API group and kind
  echo ""
  echo "Resources by API group and kind:"
  db_query "SELECT data->>'apigroup' as apigroup, data->>'kind' as kind, COUNT(*) as count FROM search.resources GROUP BY data->>'apigroup', data->>'kind' ORDER BY COUNT(*) DESC LIMIT 15;" "Resources by API group and kind breakdown"

  # Namespace statistics
  echo ""
  echo "Namespace statistics:"
  db_query "SELECT data->>'namespace' as namespace, COUNT(*) as resource_count FROM search.resources WHERE data->>'namespace' IS NOT NULL GROUP BY data->>'namespace' ORDER BY COUNT(*) DESC LIMIT 15;" "Namespace resource distribution"

  # Kubernetes node/CPU/memory summary
  echo ""
  echo "Kubernetes node/CPU/memory summary:"
  db_query "SELECT cluster, COUNT(CASE WHEN data->>'kind' = 'Node' THEN 1 END) as nodes, SUM(CASE WHEN data->>'kind' = 'Node' THEN COALESCE((data->'status'->'capacity'->>'cpu')::int, 0) ELSE 0 END) as total_cpu, ROUND(SUM(CASE WHEN data->>'kind' = 'Node' THEN COALESCE(SUBSTRING(data->'status'->'capacity'->>'memory' FROM '^[0-9]+')::bigint, 0) ELSE 0 END) / 1024.0 / 1024.0, 2) as total_memory_gb FROM search.resources WHERE data->>'kind' = 'Node' GROUP BY cluster ORDER BY nodes DESC;" "Node resource capacity by cluster"

  # === EDGES STATISTICS ===
  echo ""
  echo "=== EDGES STATISTICS ==="

  # Total edges
  echo "Total edges:"
  db_query "SELECT COUNT(*) as total_edges FROM search.edges;" "Total edge count"

  # Edges by cluster
  echo ""
  echo "Edges by cluster:"
  db_query "SELECT cluster, COUNT(*) as edge_count FROM search.edges GROUP BY cluster ORDER BY COUNT(*) DESC LIMIT 15;" "Edge distribution by cluster"

  # Edges by type
  echo ""
  echo "Edges by type:"
  db_query "SELECT edgeType, COUNT(*) as count FROM search.edges GROUP BY edgeType ORDER BY COUNT(*) DESC LIMIT 10;" "Edge type distribution"

  # Inter-cluster edges analysis
  echo ""
  echo "Inter-cluster edges analysis:"
  db_query "SELECT 'Total edges' as edge_category, COUNT(*) as count FROM search.edges;" "Edge analysis by category"

  # === POSTGRESQL DEBUG DATA ===
  echo ""
  echo "=== POSTGRESQL DEBUG DATA ==="

  # Database size and connection info
  echo "Database size and connection info:"
  db_query "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size, numbackends as connections, xact_commit, xact_rollback, blks_read, blks_hit, ROUND(blks_hit * 100.0 / NULLIF(blks_hit + blks_read, 0), 2) as cache_hit_ratio FROM pg_stat_database WHERE datname = '$DB_NAME';" "Database statistics and cache performance"

  # Table sizes (resources and edges)
  echo ""
  echo "Table sizes (resources and edges):"
  db_query "SELECT tablename, pg_size_pretty(pg_total_relation_size('search.' || tablename)) as total_size, pg_size_pretty(pg_relation_size('search.' || tablename)) as table_size, pg_size_pretty(pg_total_relation_size('search.' || tablename) - pg_relation_size('search.' || tablename)) as index_size FROM pg_tables WHERE schemaname = 'search' ORDER BY pg_total_relation_size('search.' || tablename) DESC;" "Search schema table and index sizes"

  # Index usage statistics
  echo ""
  echo "Index usage statistics:"
  db_query "SELECT schemaname, relname as tablename, indexrelname as indexname, idx_scan as scans, idx_tup_read as tuples_read, idx_tup_fetch as tuples_fetched, CASE WHEN idx_tup_read > 0 THEN ROUND(100.0 * idx_tup_fetch / idx_tup_read, 2) ELSE 0 END as efficiency_pct FROM pg_stat_user_indexes WHERE schemaname = 'search' ORDER BY idx_scan DESC;" "Search schema index usage and efficiency"

  # Running and idle queries
  echo ""
  echo "Running and idle queries:"
  db_query "SELECT state, COUNT(*) as count, ROUND(AVG(EXTRACT(epoch FROM (now() - query_start))), 2) as avg_duration_sec FROM pg_stat_activity WHERE datname = '$DB_NAME' GROUP BY state;" "Database connection state analysis"

  # Top queries by execution time (if pg_stat_statements available)
  echo ""
  echo "Top queries by execution time (if pg_stat_statements available):"
  db_query "SELECT LEFT(query, 100) as query_preview, calls, ROUND(total_exec_time::numeric, 2) as total_time_ms, ROUND(mean_exec_time::numeric, 2) as mean_time_ms, rows FROM pg_stat_statements WHERE query LIKE '%search.resources%' OR query LIKE '%search.edges%' ORDER BY total_exec_time DESC LIMIT 10;" "Top resource queries by execution time" 2>/dev/null || echo "pg_stat_statements extension not available"

  # === QUERY EXECUTION ANALYSIS ===
  echo ""
  echo "=== QUERY EXECUTION ANALYSIS ==="

  # Get random cluster and UID for realistic query plans
  echo "Getting sample data for query performance analysis:"
  RANDOM_CLUSTER=$(kubectl exec -n $POSTGRES_NS $POSTGRES_POD -- psql -d $DB_NAME -U $DB_USER -t -c "SELECT cluster FROM search.resources ORDER BY RANDOM() LIMIT 1;" 2>/dev/null | tr -d ' ')
  RANDOM_UID=$(kubectl exec -n $POSTGRES_NS $POSTGRES_POD -- psql -d $DB_NAME -U $DB_USER -t -c "SELECT uid FROM search.resources ORDER BY RANDOM() LIMIT 1;" 2>/dev/null | tr -d ' ')

  # Log sample data retrieval
  echo "$(date '+%H:%M:%S') SAMPLE_DATA: cluster=$RANDOM_CLUSTER, uid=$RANDOM_UID" >> "${EXECUTION_LOG:-/dev/null}"

  if [ ! -z "$RANDOM_CLUSTER" ] && [ ! -z "$RANDOM_UID" ]; then
    echo "Testing query performance with cluster: $RANDOM_CLUSTER, uid: $RANDOM_UID"

    # Test JSON ? operator performance
    echo ""
    echo "Testing JSON ? operator performance:"
    db_query "EXPLAIN ANALYZE SELECT COUNT(*) FROM search.resources WHERE data ? 'kind' AND cluster = '$RANDOM_CLUSTER';" "JSON ? operator query performance analysis"

    # Test JSON ->> operator performance
    echo ""
    echo "Testing JSON ->> operator performance:"
    db_query "EXPLAIN ANALYZE SELECT COUNT(*) FROM search.resources WHERE data->>'kind' = 'Pod' AND cluster = '$RANDOM_CLUSTER';" "JSON ->> operator query performance analysis"

    # Test specific UID lookup
    echo ""
    echo "Testing specific UID lookup performance:"
    db_query "EXPLAIN ANALYZE SELECT cluster, uid, data->>'kind', data->>'name' FROM search.resources WHERE uid = '$RANDOM_UID';" "UID-based resource lookup performance analysis"

  else
    echo "Could not retrieve sample data for query analysis"
  fi

  echo "PostgreSQL diagnostic collection completed at $(date)"
  echo ""

else
  echo "PostgreSQL pod not found - skipping database diagnostics"
fi

# Helper function for log analysis with execution logging
log_analysis() {
  local log_source="$1"
  local description="$2"
  local timestamp=$(date '+%H:%M:%S')

  # Log the analysis attempt
  echo "[$timestamp] LOG_ANALYSIS: $description" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] LOG_SOURCE: $log_source" >> "${EXECUTION_LOG:-/dev/null}"

  # Execute log collection and analysis
  local raw_logs=$(eval "$log_source" 2>&1)
  local exit_code=$?

  # Log the raw log collection status
  echo "[$timestamp] LOG_COLLECTION_EXIT_CODE: $exit_code" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] LOG_LINE_COUNT: $(echo "$raw_logs" | wc -l)" >> "${EXECUTION_LOG:-/dev/null}"

  # Process logs and capture analysis results
  local analysis_output=$(echo "$raw_logs" | python3 -c "
import sys
import re
from collections import defaultdict

batch_sizes = []
processing_times = []
error_counts = defaultdict(int)

for line in sys.stdin:
    if 'batch' in line.lower():
        size_match = re.search(r'batch.*?(\d+).*?items', line)
        if size_match:
            batch_sizes.append(int(size_match.group(1)))

    time_match = re.search(r'(\d+\.?\d*)ms', line)
    if time_match:
        processing_times.append(float(time_match.group(1)))

    if re.search(r'error|failed|timeout', line, re.I):
        error_type = 'connection' if 'connection' in line else 'processing' if 'processing' in line else 'other'
        error_counts[error_type] += 1

if batch_sizes:
    print(f'Batch size stats: avg={sum(batch_sizes)/len(batch_sizes):.0f}, max={max(batch_sizes)}, count={len(batch_sizes)}')
if processing_times:
    print(f'Processing time stats: avg={sum(processing_times)/len(processing_times):.1f}ms, max={max(processing_times):.1f}ms')
if error_counts:
    print(f'Error breakdown: {dict(error_counts)}')
else:
    print('No significant errors detected in recent logs')
")

  # Log analysis results
  echo "[$timestamp] LOG_ANALYSIS_RESULTS: $analysis_output" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] LOG_ANALYSIS_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"

  # Display analysis results
  echo "$analysis_output"
}

# Enhanced log analysis with multiple time windows and targeted filtering
echo "=== INDEXER PROCESSING PATTERNS ==="

# Helper function for intelligent log analysis with time windows
intelligent_log_analysis() {
  local time_window="$1"
  local description="$2"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] INTELLIGENT_LOG_ANALYSIS: $description ($time_window)" >> "${EXECUTION_LOG:-/dev/null}"

  # Get all indexer pods for comprehensive analysis
  local indexer_pods=$(kubectl get pods -l name=search-indexer -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null)
  local pod_count=$(echo "$indexer_pods" | wc -l)

  echo "[$timestamp] INDEXER_PODS_FOUND: $pod_count" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] INDEXER_PODS: $indexer_pods" >> "${EXECUTION_LOG:-/dev/null}"

  # Collect logs from all pods with time-based filtering
  local all_logs=""
  if [ ! -z "$indexer_pods" ]; then
    while IFS= read -r pod_line; do
      if [ ! -z "$pod_line" ]; then
        local ns=$(echo "$pod_line" | awk '{print $1}')
        local pod=$(echo "$pod_line" | awk '{print $2}')
        if [ ! -z "$ns" ] && [ ! -z "$pod" ]; then
          local pod_logs=$(kubectl logs -n "$ns" "$pod" --since="$time_window" 2>/dev/null)
          if [ ! -z "$pod_logs" ]; then
            all_logs="$all_logs\n$pod_logs"
          fi
        fi
      fi
    done <<< "$indexer_pods"
  fi

  # Log raw collection stats
  local total_lines=$(echo -e "$all_logs" | wc -l)
  echo "[$timestamp] RAW_LOG_LINES_COLLECTED: $total_lines" >> "${EXECUTION_LOG:-/dev/null}"

  # Apply intelligent filtering for indexer-relevant patterns
  local filtered_logs=$(echo -e "$all_logs" | grep -E "(batch|process|sync|request|error|warn|performance|ms|seconds|database|postgres|index)" 2>/dev/null || echo "")
  local filtered_lines=$(echo "$filtered_logs" | wc -l)

  echo "[$timestamp] FILTERED_LOG_LINES: $filtered_lines" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] LOG_FILTER_PATTERN: batch|process|sync|request|error|warn|performance|ms|seconds|database|postgres|index" >> "${EXECUTION_LOG:-/dev/null}"

  # Perform pattern analysis on filtered logs
  local analysis_output=$(echo "$filtered_logs" | python3 -c "
import sys
import re
from collections import defaultdict
from datetime import datetime

# Enhanced pattern matching for indexer-specific metrics
batch_sizes = []
processing_times = []
error_counts = defaultdict(int)
request_patterns = defaultdict(int)
sync_patterns = []
database_operations = []

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue

    # Batch processing patterns
    batch_match = re.search(r'(?:batch|processing|handled)\s+(\d+)\s+(?:items|resources|requests)', line, re.I)
    if batch_match:
        batch_sizes.append(int(batch_match.group(1)))

    # Performance timing patterns (more comprehensive)
    time_patterns = [
        r'(\d+(?:\.\d+)?)\s*ms',
        r'(\d+(?:\.\d+)?)\s*milliseconds',
        r'took\s+(\d+(?:\.\d+)?)\s*(?:ms|seconds)',
        r'duration[:\s]+(\d+(?:\.\d+)?)',
        r'processed\s+in\s+(\d+(?:\.\d+)?)'
    ]
    for pattern in time_patterns:
        time_match = re.search(pattern, line, re.I)
        if time_match:
            processing_times.append(float(time_match.group(1)))
            break

    # Error and warning classification
    if re.search(r'error|failed|timeout|exception', line, re.I):
        error_type = 'database' if re.search(r'postgres|sql|database|connection', line, re.I) else \
                    'network' if re.search(r'network|connection|timeout', line, re.I) else \
                    'processing' if re.search(r'process|batch|sync', line, re.I) else \
                    'other'
        error_counts[error_type] += 1

    # Request processing patterns
    if re.search(r'request|sync|index', line, re.I):
        req_type = 'sync' if re.search(r'sync|resync', line, re.I) else \
                  'index' if re.search(r'index|indexing', line, re.I) else \
                  'request'
        request_patterns[req_type] += 1

    # Database operation indicators
    if re.search(r'postgres|database|sql|query', line, re.I):
        database_operations.append(line[:100])  # Keep sample for analysis

# Generate comprehensive analysis report
print(f'=== LOG ANALYSIS RESULTS ($description) ===')
print(f'Total relevant log entries analyzed: {sum(batch_sizes) if batch_sizes else 0 + len(processing_times) + sum(error_counts.values()) + sum(request_patterns.values())}')

if batch_sizes:
    print(f'BATCH PROCESSING: avg_size={sum(batch_sizes)/len(batch_sizes):.0f}, max={max(batch_sizes)}, total_batches={len(batch_sizes)}')
else:
    print('BATCH PROCESSING: No batch processing patterns detected')

if processing_times:
    avg_time = sum(processing_times)/len(processing_times)
    print(f'PERFORMANCE: avg={avg_time:.1f}ms, max={max(processing_times):.1f}ms, min={min(processing_times):.1f}ms, samples={len(processing_times)}')
else:
    print('PERFORMANCE: No timing patterns detected')

if error_counts:
    print(f'ERRORS/WARNINGS: {dict(error_counts)} (total: {sum(error_counts.values())})')
else:
    print('ERRORS/WARNINGS: No error patterns detected')

if request_patterns:
    print(f'REQUEST PATTERNS: {dict(request_patterns)} (total: {sum(request_patterns.values())})')
else:
    print('REQUEST PATTERNS: No request patterns detected')

if database_operations:
    print(f'DATABASE ACTIVITY: {len(database_operations)} database-related log entries detected')
else:
    print('DATABASE ACTIVITY: No database operations detected in logs')
")

  # Log analysis results
  echo "[$timestamp] INTELLIGENT_ANALYSIS_RESULTS:" >> "${EXECUTION_LOG:-/dev/null}"
  echo "$analysis_output" >> "${EXECUTION_LOG:-/dev/null}"
  echo "[$timestamp] INTELLIGENT_LOG_ANALYSIS_COMPLETE" >> "${EXECUTION_LOG:-/dev/null}"
  echo "" >> "${EXECUTION_LOG:-/dev/null}"

  # Display results
  echo "$analysis_output"
}

# Multi-window analysis for comprehensive insights
echo "Analyzing indexer logs across multiple time windows..."

echo ""
echo "=== RECENT ACTIVITY (Last 10 minutes) ==="
intelligent_log_analysis "10m" "Recent indexer activity analysis"

echo ""
echo "=== SHORT TERM PATTERNS (Last 30 minutes) ==="
intelligent_log_analysis "30m" "Short-term indexer pattern analysis"

echo ""
echo "=== BROADER CONTEXT (Last 1 hour) ==="
intelligent_log_analysis "1h" "Long-term indexer context analysis"