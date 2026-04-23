#!/bin/bash
# Search Architecture Symptom-Based Routing
# Intelligently routes user-reported symptoms to appropriate impact assessments
# Provides guidance on which assessments to run based on observed issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHITECTURE_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$(dirname "$ARCHITECTURE_DIR")"

echo "=== Search Architecture Symptom Routing ==="
echo "Analyzes symptoms and routes to appropriate impact assessments"
echo ""

# Function to display usage
show_usage() {
    cat << 'EOF'
Usage: route-symptoms.sh [SYMPTOM]

Available symptom categories:
  api-slow           - GraphQL queries taking too long
  api-errors         - Authentication or GraphQL errors
  query-timeouts     - Search queries timing out
  new-cluster        - Recently added cluster causing issues
  cluster-removed    - Cluster removal causing problems
  indexer-slow       - Slow data ingestion or processing
  database-issues    - PostgreSQL errors or slow queries
  component-restart  - Search components restarting frequently
  operator-issues    - Operator reconciliation problems
  network-problems   - Cross-cluster connectivity issues
  everything-slow    - System-wide performance degradation
  memory-pressure    - High memory usage across components
  deployment-failed  - Component deployment failures

Examples:
  ./route-symptoms.sh api-slow
  ./route-symptoms.sh new-cluster
  ./route-symptoms.sh everything-slow

If no symptom is provided, interactive mode will guide you through symptom identification.
EOF
}

# Function for interactive symptom identification
interactive_symptom_detection() {
    echo "=== Interactive Symptom Detection ==="
    echo ""
    echo "Let's identify what you're experiencing:"
    echo ""

    # Performance-related symptoms
    echo "1. Performance Issues:"
    echo "   a) Search queries are slow or timing out"
    echo "   b) Dashboard/UI is taking too long to load"
    echo "   c) Data seems stale or not updating"
    echo "   d) Everything feels sluggish"
    echo ""

    # Operational events
    echo "2. Recent Changes:"
    echo "   e) Added new clusters to ACM"
    echo "   f) Removed clusters from ACM"
    echo "   g) Upgraded ACM or search components"
    echo "   h) Changed policies or RBAC settings"
    echo ""

    # Component-specific issues
    echo "3. Component Problems:"
    echo "   i) Search pods restarting frequently"
    echo "   j) Database connection errors"
    echo "   k) Authentication/permission errors"
    echo "   l) Network connectivity problems"
    echo ""

    read -p "Enter the letter of your primary symptom (a-l): " symptom_choice

    case "$symptom_choice" in
        a) echo "Routing to: API + Indexer assessment"; route_to_assessments "api-slow" ;;
        b) echo "Routing to: API + RBAC assessment"; route_to_assessments "api-errors" ;;
        c) echo "Routing to: Indexer + Collector assessment"; route_to_assessments "indexer-slow" ;;
        d) echo "Routing to: Comprehensive assessment"; route_to_assessments "everything-slow" ;;
        e) echo "Routing to: Collector + Indexer assessment"; route_to_assessments "new-cluster" ;;
        f) echo "Routing to: Operator + Indexer assessment"; route_to_assessments "cluster-removed" ;;
        g) echo "Routing to: Operator + All components assessment"; route_to_assessments "operator-issues" ;;
        h) echo "Routing to: API + Operator assessment"; route_to_assessments "api-errors" ;;
        i) echo "Routing to: Operator + Component assessment"; route_to_assessments "component-restart" ;;
        j) echo "Routing to: Indexer + Database assessment"; route_to_assessments "database-issues" ;;
        k) echo "Routing to: API + RBAC assessment"; route_to_assessments "api-errors" ;;
        l) echo "Routing to: Collector + Network assessment"; route_to_assessments "network-problems" ;;
        *) echo "Invalid choice. Please run the script again and choose a-l."; exit 1 ;;
    esac
}

# Function to route symptoms to appropriate assessments
route_to_assessments() {
    local symptom="$1"

    echo ""
    echo "=== Routing Analysis for Symptom: $symptom ==="

    case "$symptom" in
        "api-slow"|"query-timeouts")
            echo "🎯 Primary Cause: GraphQL query performance, RBAC overhead, or database pressure"
            echo "📊 Recommended Assessments:"
            echo "   1. search-api-impact (Primary) - GraphQL optimization, RBAC analysis"
            echo "   2. search-indexer-impact (Secondary) - Database query performance"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-api-impact && ./scripts/generate-assessment.sh"
            echo "   cd $SKILLS_DIR/search-indexer-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   API queries → PostgreSQL database → Query complexity affects response time"
            echo "   RBAC evaluation overhead can dominate query latency"
            ;;

        "api-errors")
            echo "🎯 Primary Cause: Authentication, RBAC configuration, or API server errors"
            echo "📊 Recommended Assessments:"
            echo "   1. search-api-impact (Primary) - RBAC analysis, authentication patterns"
            echo "   2. search-operator-impact (Secondary) - Configuration and deployment health"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-api-impact && ./scripts/generate-assessment.sh"
            echo "   cd $SKILLS_DIR/search-operator-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   Authentication flow → RBAC evaluation → API response"
            echo "   Operator manages API server configuration and RBAC policies"
            ;;

        "new-cluster"|"cluster-added")
            echo "🎯 Primary Cause: Collector deployment, connection stress, or indexer overload"
            echo "📊 Recommended Assessments:"
            echo "   1. search-collector-impact (Primary) - Connection stress, networking"
            echo "   2. search-indexer-impact (Secondary) - Processing load, database pressure"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-collector-impact && ./scripts/generate-assessment.sh"
            echo "   cd $SKILLS_DIR/search-indexer-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   New cluster → Collector deployment → Data sync → Indexer processing"
            echo "   Connection pool exhaustion and database load common with rapid cluster additions"
            ;;

        "cluster-removed"|"cluster-cleanup")
            echo "🎯 Primary Cause: Operator addon cleanup, data retention, or reconciliation issues"
            echo "📊 Recommended Assessments:"
            echo "   1. search-operator-impact (Primary) - Addon management, reconciliation"
            echo "   2. search-indexer-impact (Secondary) - Data cleanup, database consistency"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-operator-impact && ./scripts/generate-assessment.sh"
            echo "   cd $SKILLS_DIR/search-indexer-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   Cluster removal → Operator cleanup → ManagedClusterAddOn deletion → Data purge"
            echo "   Reconciliation loops can occur if cleanup fails"
            ;;

        "indexer-slow"|"data-stale")
            echo "🎯 Primary Cause: Database pressure, batch processing delays, or relationship computation"
            echo "📊 Recommended Assessments:"
            echo "   1. search-indexer-impact (Primary) - PostgreSQL diagnostics, processing efficiency"
            echo "   2. search-collector-impact (Secondary) - Data sync rate, collector performance"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-indexer-impact && ./scripts/generate-assessment.sh"
            echo "   cd $SKILLS_DIR/search-collector-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   Collectors sync → Indexer processing → Database storage → Relationship computation"
            echo "   Database bottlenecks cascade to both ingestion and query performance"
            ;;

        "database-issues"|"postgres-errors")
            echo "🎯 Primary Cause: PostgreSQL connection limits, query performance, or resource pressure"
            echo "📊 Recommended Assessments:"
            echo "   1. search-indexer-impact (Primary) - Comprehensive PostgreSQL diagnostics"
            echo "   2. search-api-impact (Secondary) - Database query performance from API side"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-indexer-impact && ./scripts/generate-assessment.sh"
            echo "   cd $SKILLS_DIR/search-api-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   PostgreSQL is central hub → Both indexer writes and API reads affected"
            echo "   Connection limits, query complexity, and resource usage need analysis"
            ;;

        "component-restart"|"pod-crashes")
            echo "🎯 Primary Cause: Resource pressure, operator configuration, or deployment issues"
            echo "📊 Recommended Assessments:"
            echo "   1. search-operator-impact (Primary) - Component lifecycle, resource management"
            echo "   2. search-indexer-impact (Secondary) - Resource utilization, stability analysis"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-operator-impact && ./scripts/generate-assessment.sh"
            echo "   cd $SKILLS_DIR/search-indexer-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   Operator manages deployment → Component health → Resource allocation"
            echo "   Restart loops often indicate resource limits or configuration issues"
            ;;

        "operator-issues"|"reconciliation-problems")
            echo "🎯 Primary Cause: Operator reconciliation delays, leader election, or addon deployment"
            echo "📊 Recommended Assessments:"
            echo "   1. search-operator-impact (Primary) - Reconciliation performance, resource analysis"
            echo "   2. search-indexer-impact (Secondary) - Component deployment effects"
            echo "   3. search-api-impact (Tertiary) - Configuration impacts"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-operator-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   Operator reconciles → Component deployments → Addon distribution → System health"
            echo "   Operator issues cascade to all managed components"
            ;;

        "network-problems"|"connectivity-issues")
            echo "🎯 Primary Cause: Cross-cluster networking, collector connectivity, or API accessibility"
            echo "📊 Recommended Assessments:"
            echo "   1. search-collector-impact (Primary) - Cross-cluster network analysis"
            echo "   2. search-api-impact (Secondary) - Client connectivity patterns"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-collector-impact && ./scripts/generate-assessment.sh"
            echo "   cd $SKILLS_DIR/search-api-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   Managed clusters → Hub networking → Collector sync → API access"
            echo "   Network issues affect both data collection and query access"
            ;;

        "everything-slow"|"system-wide"|"performance-degradation")
            echo "🎯 Primary Cause: System-wide bottleneck, likely database or resource pressure"
            echo "📊 Recommended Assessments:"
            echo "   1. search-indexer-impact (Primary) - Database and central processing"
            echo "   2. search-api-impact (High) - Query performance and user impact"
            echo "   3. search-operator-impact (Medium) - Component management health"
            echo "   4. search-collector-impact (Medium) - Fleet-wide collection efficiency"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   # Use orchestrator for comprehensive analysis:"
            echo "   cd $SKILLS_DIR/search-architecture && ./scripts/orchestrate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   System-wide issues typically indicate central bottlenecks (database, resources)"
            echo "   Comprehensive assessment needed to identify root cause and cascade effects"
            ;;

        "memory-pressure"|"resource-pressure")
            echo "🎯 Primary Cause: Resource limits, memory leaks, or scaling requirements"
            echo "📊 Recommended Assessments:"
            echo "   1. search-indexer-impact (Primary) - Database resource utilization"
            echo "   2. search-operator-impact (High) - Component resource management"
            echo "   3. search-api-impact (Medium) - API server resource usage"
            echo ""
            echo "🔧 Quick Commands:"
            echo "   cd $SKILLS_DIR/search-indexer-impact && ./scripts/generate-assessment.sh"
            echo "   cd $SKILLS_DIR/search-operator-impact && ./scripts/generate-assessment.sh"
            echo ""
            echo "📋 Architecture Context:"
            echo "   Resource pressure cascades → Component instability → Performance degradation"
            echo "   Database and operator typically consume most resources"
            ;;

        *)
            echo "❌ Unknown symptom: $symptom"
            echo ""
            echo "Available symptoms: api-slow, api-errors, query-timeouts, new-cluster, cluster-removed,"
            echo "                   indexer-slow, database-issues, component-restart, operator-issues,"
            echo "                   network-problems, everything-slow, memory-pressure"
            echo ""
            echo "Run without arguments for interactive symptom detection."
            exit 1
            ;;
    esac

    echo ""
    echo "💡 Next Steps:"
    echo "   1. Run the recommended assessments above"
    echo "   2. Use correlation analysis: scripts/correlate-results.sh"
    echo "   3. Review architectural patterns in correlation report"
    echo ""
    echo "🔍 Need help interpreting results?"
    echo "   Each assessment generates detailed JSON reports with explanations"
    echo "   Correlation analysis provides cross-component insights"
}

# Main logic
if [ $# -eq 0 ]; then
    # No arguments - enter interactive mode
    interactive_symptom_detection
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
else
    # Route the provided symptom
    route_to_assessments "$1"
fi