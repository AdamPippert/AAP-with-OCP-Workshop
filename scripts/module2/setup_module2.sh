#!/bin/bash
# Module 2 Setup Script
# Prepares environment and runs all Module 2 exercises

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
PLAYBOOK_DIR="$WORKSHOP_DIR/playbooks/module2"

# Default values
NAMESPACE="${1:-ims-workshop-$(date +%s)}"
ENVIRONMENT="${2:-dev}"
MAINFRAME_HOST="${3:-mainframe.example.com}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      Module 2 Setup                         ║${NC}"
    echo -e "${BLUE}║        Idempotent Resource Management and RBAC              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
}

print_exercise_header() {
    local exercise_name="$1"
    echo -e "\n${YELLOW}─────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW} $exercise_name${NC}"
    echo -e "${YELLOW}─────────────────────────────────────────────────────────────${NC}\n"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if ansible-playbook is available
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "ansible-playbook is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if workshop directory exists
    if [ ! -d "$WORKSHOP_DIR" ]; then
        log_error "Workshop directory not found: $WORKSHOP_DIR"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

run_exercise() {
    local exercise_number="$1"
    local exercise_name="$2"
    local playbook_file="$3"
    local description="$4"
    
    print_exercise_header "Exercise 2-$exercise_number: $exercise_name"
    log_info "$description"
    
    local playbook_path="$PLAYBOOK_DIR/$playbook_file"
    
    if [ ! -f "$playbook_path" ]; then
        log_error "Playbook not found: $playbook_path"
        return 1
    fi
    
    log_info "Running playbook: $playbook_file"
    
    # Run the playbook with appropriate variables
    if ansible-playbook "$playbook_path" \
        -e "workshop_namespace=$NAMESPACE" \
        -e "workshop_environment=$ENVIRONMENT" \
        -e "ims_mainframe_host=$MAINFRAME_HOST" \
        -v; then
        log_success "Exercise 2-$exercise_number completed successfully"
        return 0
    else
        log_error "Exercise 2-$exercise_number failed"
        return 1
    fi
}

show_environment_info() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Environment Information                   ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${YELLOW}Workshop Configuration:${NC}"
    echo -e "  Namespace: $NAMESPACE"
    echo -e "  Environment: $ENVIRONMENT"
    echo -e "  Mainframe Host: $MAINFRAME_HOST"
    
    echo -e "\n${YELLOW}Cluster Information:${NC}"
    kubectl cluster-info --context=$(kubectl config current-context) | head -2
    
    echo -e "\n${YELLOW}Current Context:${NC}"
    kubectl config current-context
    
    echo ""
}

run_validation() {
    print_exercise_header "Module 2 Validation"
    log_info "Running comprehensive validation of Module 2 completion"
    
    local validation_script="$SCRIPT_DIR/validate_module2.sh"
    
    if [ -f "$validation_script" ]; then
        if bash "$validation_script" "$NAMESPACE" "$ENVIRONMENT"; then
            log_success "Module 2 validation passed"
            return 0
        else
            log_warning "Module 2 validation found issues"
            return 1
        fi
    else
        log_warning "Validation script not found, skipping validation"
        return 0
    fi
}

cleanup_on_failure() {
    log_warning "Cleaning up resources due to failure..."
    
    # Attempt to delete the namespace if it was created
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_info "Deleting namespace: $NAMESPACE"
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=60s
    fi
}

main() {
    print_header
    
    log_info "Starting Module 2 setup for AAP with OpenShift Container Platform"
    log_info "This module focuses on idempotent resource management and RBAC patterns"
    
    # Trap cleanup on failure
    trap cleanup_on_failure ERR
    
    # Check prerequisites
    check_prerequisites
    
    # Show environment information
    show_environment_info
    
    # Confirm before proceeding
    echo -e "${YELLOW}This will create resources in your OpenShift cluster.${NC}"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled by user"
        exit 0
    fi
    
    # Run exercises in sequence
    local exercises_passed=0
    local total_exercises=4
    
    # Exercise 1: Idempotent Deployment
    if run_exercise "1" "Idempotent Deployment" "exercise2-1-idempotent-deployment.yml" \
        "Deploy IMS connector service with idempotent patterns using redhat.openshift collection"; then
        ((exercises_passed++))
    fi
    
    # Exercise 2: RBAC Automation
    if run_exercise "2" "RBAC Automation" "exercise2-2-rbac-automation.yml" \
        "Create automated service account provisioning with comprehensive RBAC"; then
        ((exercises_passed++))
    fi
    
    # Exercise 3: Rollback Patterns
    if run_exercise "3" "Rollback Patterns" "exercise2-3-rollback-patterns.yml" \
        "Implement rollback capabilities using block-rescue-always patterns"; then
        ((exercises_passed++))
    fi
    
    # Exercise 4: Validation
    if run_exercise "4" "Validation" "exercise2-4-validation.yml" \
        "Comprehensive validation and peer review of Module 2 implementation"; then
        ((exercises_passed++))
    fi
    
    # Run additional validation
    if run_validation; then
        log_success "Module 2 validation completed successfully"
    fi
    
    # Display completion summary
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Module 2 Complete                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${YELLOW}Exercises Completed: ${GREEN}$exercises_passed/$total_exercises${NC}"
    
    if [ $exercises_passed -eq $total_exercises ]; then
        log_success "All Module 2 exercises completed successfully!"
        echo -e "\n${GREEN}✓ Idempotent deployment patterns mastered${NC}"
        echo -e "${GREEN}✓ RBAC automation implemented${NC}"
        echo -e "${GREEN}✓ Rollback capabilities demonstrated${NC}"
        echo -e "${GREEN}✓ Production-ready resource management achieved${NC}"
        
        echo -e "\n${BLUE}Next Steps:${NC}"
        echo -e "1. Review the deployed resources in namespace: ${YELLOW}$NAMESPACE${NC}"
        echo -e "2. Experiment with different failure scenarios"
        echo -e "3. Proceed to Module 3 for advanced automation patterns"
        
        echo -e "\n${BLUE}Useful Commands:${NC}"
        echo -e "  kubectl get all -n $NAMESPACE"
        echo -e "  kubectl describe deployment ims-connector -n $NAMESPACE"
        echo -e "  kubectl get rolebindings -n $NAMESPACE"
        echo -e "  ./scripts/module2/validate_module2.sh $NAMESPACE $ENVIRONMENT"
        
    else
        log_warning "Some exercises did not complete successfully"
        echo -e "\n${YELLOW}Please review the logs above and rerun failed exercises${NC}"
        exit 1
    fi
    
    # Remove trap
    trap - ERR
}

# Usage information
usage() {
    echo "Usage: $0 [NAMESPACE] [ENVIRONMENT] [MAINFRAME_HOST]"
    echo ""
    echo "Parameters:"
    echo "  NAMESPACE       - Kubernetes namespace (default: ims-workshop-<timestamp>)"
    echo "  ENVIRONMENT     - Workshop environment: dev, test, prod (default: dev)"
    echo "  MAINFRAME_HOST  - IMS mainframe hostname (default: mainframe.example.com)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use defaults"
    echo "  $0 my-workshop dev                    # Custom namespace, dev environment"
    echo "  $0 prod-workshop prod mainframe.corp.com  # Production setup"
    echo ""
    exit 1
}

# Handle help requests
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
fi

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi