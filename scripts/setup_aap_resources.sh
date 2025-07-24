#!/bin/bash

# Standalone AAP Resource Setup Script
# This script can be run independently to set up AAP resources for the workshop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Check if environment file exists
if [[ ! -f "${ENV_FILE}" ]]; then
    error ".env file not found. Please run ./scripts/exercise0/setup_workshop.sh first"
fi

# Source the AAP functions from the main setup script
source "${SCRIPT_DIR}/exercise0/setup_workshop.sh"

check_aap_prerequisites() {
    log "Checking AAP prerequisites..."
    
    source "${ENV_FILE}"
    
    if [[ -z "${AAP_URL:-}" ]]; then
        error "AAP_URL not found in environment. Please run setup_workshop.sh first"
    fi
    
    if [[ -z "${AAP_USERNAME:-}" && -z "${AAP_TOKEN:-}" ]]; then
        error "Neither AAP_USERNAME nor AAP_TOKEN found in environment"
    fi
    
    if [[ -z "${WORKSHOP_GUID:-}" ]]; then
        error "WORKSHOP_GUID not found in environment. Please run setup_workshop.sh first"
    fi
    
    # Test AAP connectivity
    if ! curl -k -s --connect-timeout 10 "${AAP_URL}/api/v2/ping/" >/dev/null; then
        error "Cannot connect to AAP Controller at ${AAP_URL}"
    fi
    
    log "AAP prerequisites check passed"
}

show_aap_resources() {
    log "Displaying created AAP resources..."
    
    source "${ENV_FILE}"
    
    echo
    echo "========================================"
    echo "  AAP WORKSHOP RESOURCES CREATED"
    echo "========================================"
    echo
    echo "Controller URL: ${AAP_URL}"
    echo "Workshop GUID: ${WORKSHOP_GUID}"
    echo
    
    if [[ -n "${AAP_PROJECT_ID:-}" ]]; then
        echo "Project: AAP-Workshop-${WORKSHOP_GUID} (ID: ${AAP_PROJECT_ID})"
    fi
    
    if [[ -n "${AAP_INVENTORY_ID:-}" ]]; then
        echo "Inventory: Workshop-OpenShift-${WORKSHOP_GUID} (ID: ${AAP_INVENTORY_ID})"
    fi
    
    if [[ -n "${AAP_CREDENTIAL_ID:-}" ]]; then
        echo "Credential: OpenShift-${WORKSHOP_GUID} (ID: ${AAP_CREDENTIAL_ID})"
    fi
    
    echo
    echo "Job Templates Created:"
    echo "  • Module1-Dynamic-Inventory-${WORKSHOP_GUID}"
    echo "  • Module1-Multi-Cluster-${WORKSHOP_GUID}"
    echo "  • Module1-Advanced-Grouping-${WORKSHOP_GUID}"
    echo "  • Module1-Troubleshooting-${WORKSHOP_GUID}"
    echo "  • Module2-RBAC-Setup-${WORKSHOP_GUID}"
    echo "  • Module2-RBAC-Automation-${WORKSHOP_GUID}"
    echo "  • Module2-Idempotent-Deploy-${WORKSHOP_GUID}"
    echo "  • Module3-Template-Engine-${WORKSHOP_GUID}"
    echo "  • Module3-Error-Handling-${WORKSHOP_GUID}"
    echo "  • Module3-Troubleshooting-${WORKSHOP_GUID}"
    echo
    echo "Access your AAP Controller to view and run these templates:"
    echo "  ${AAP_URL}/#/templates"
    echo
}

cleanup_aap_resources() {
    log "WARNING: This will delete ALL workshop resources from AAP"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled"
        exit 0
    fi
    
    source "${ENV_FILE}"
    
    log "Cleaning up AAP resources..."
    
    # Delete job templates
    log "Deleting job templates..."
    local templates=$(aap_api_call "GET" "/job_templates/?name__contains=${WORKSHOP_GUID}" "")
    echo "${templates}" | grep -o '"id":[0-9]*' | cut -d':' -f2 | while read -r template_id; do
        if [[ -n "${template_id}" ]]; then
            aap_api_call "DELETE" "/job_templates/${template_id}/" ""
            log "Deleted job template ID: ${template_id}"
        fi
    done
    
    # Delete project
    if [[ -n "${AAP_PROJECT_ID:-}" ]]; then
        log "Deleting project ID: ${AAP_PROJECT_ID}"
        aap_api_call "DELETE" "/projects/${AAP_PROJECT_ID}/" ""
    fi
    
    # Delete inventory  
    if [[ -n "${AAP_INVENTORY_ID:-}" ]]; then
        log "Deleting inventory ID: ${AAP_INVENTORY_ID}"
        aap_api_call "DELETE" "/inventories/${AAP_INVENTORY_ID}/" ""
    fi
    
    # Delete credential
    if [[ -n "${AAP_CREDENTIAL_ID:-}" ]]; then
        log "Deleting credential ID: ${AAP_CREDENTIAL_ID}"
        aap_api_call "DELETE" "/credentials/${AAP_CREDENTIAL_ID}/" ""
    fi
    
    log "AAP resources cleanup completed"
}

usage() {
    cat << EOF
AAP Workshop Resource Setup Script

USAGE:
    $0 [COMMAND]

COMMANDS:
    setup       Set up all AAP resources for the workshop (default)
    show        Display information about created resources
    cleanup     Remove all workshop resources from AAP
    help        Show this help message

EXAMPLES:
    $0 setup         # Create all AAP resources
    $0 show          # Show created resources  
    $0 cleanup       # Remove all resources

DESCRIPTION:
    This script manages AAP (Ansible Automation Platform) resources for the
    Advanced AAP 2.5 with OpenShift workshop. It creates projects, inventories,
    credentials, and job templates based on the workshop exercises.

PREREQUISITES:
    - Run ./scripts/exercise0/setup_workshop.sh first
    - AAP Controller must be accessible
    - Valid AAP credentials in .env file

EOF
}

main() {
    local command="${1:-setup}"
    
    case "${command}" in
        setup)
            check_aap_prerequisites
            setup_aap_resources
            show_aap_resources
            ;;
        show)
            show_aap_resources
            ;;
        cleanup)
            check_aap_prerequisites
            cleanup_aap_resources
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log "ERROR: Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

main "$@"