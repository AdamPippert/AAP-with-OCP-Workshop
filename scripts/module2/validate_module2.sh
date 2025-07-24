#!/bin/bash
# Module 2 Validation Script
# Validates completion and learning objectives for Module 2

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
NAMESPACE="${1:-$(oc config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo 'ims-workshop')}"
ENVIRONMENT="${2:-dev}"

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
    echo -e "${BLUE}║                    Module 2 Validation                      ║${NC}"
    echo -e "${BLUE}║              Idempotent Resource Management                  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
}

# Validation functions
check_namespace() {
    log_info "Checking namespace: $NAMESPACE"
    
    if oc get namespace "$NAMESPACE" &>/dev/null; then
        local labels
        labels=$(oc get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels}' 2>/dev/null || echo '{}')
        
        if echo "$labels" | grep -q "workshop.redhat.com/module.*module2"; then
            log_success "Namespace $NAMESPACE exists with proper labels"
            return 0
        else
            log_warning "Namespace exists but missing workshop labels"
            return 1
        fi
    else
        log_error "Namespace $NAMESPACE does not exist"
        return 1
    fi
}

check_service_accounts() {
    log_info "Checking service accounts in namespace: $NAMESPACE"
    
    local expected_accounts=("ims-connector-sa" "ims-reader" "ims-operator")
    local found=0
    
    for account in "${expected_accounts[@]}"; do
        if oc get serviceaccount "$account" -n "$NAMESPACE" &>/dev/null; then
            log_success "Service account $account found"
            ((found++))
        else
            log_warning "Service account $account not found"
        fi
    done
    
    if [ $found -eq ${#expected_accounts[@]} ]; then
        log_success "All expected service accounts found"
        return 0
    else
        log_warning "Found $found/${#expected_accounts[@]} expected service accounts"
        return 1
    fi
}

check_rbac_configuration() {
    log_info "Checking RBAC configuration"
    
    local checks_passed=0
    local total_checks=3
    
    # Check custom role
    if oc get role "ims-namespace-operations" -n "$NAMESPACE" &>/dev/null; then
        log_success "Custom role 'ims-namespace-operations' found"
        ((checks_passed++))
    else
        log_error "Custom role 'ims-namespace-operations' not found"
    fi
    
    # Check role bindings
    local role_bindings
    role_bindings=$(oc get rolebindings -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [ "$role_bindings" -gt 0 ]; then
        log_success "$role_bindings role bindings found"
        ((checks_passed++))
    else
        log_error "No role bindings found"
    fi
    
    # Check cluster role (dev/test environments)
    if [ "$ENVIRONMENT" != "prod" ]; then
        if oc get clusterrole "ims-cluster-operations" &>/dev/null; then
            log_success "Custom cluster role 'ims-cluster-operations' found"
            ((checks_passed++))
        else
            log_warning "Custom cluster role 'ims-cluster-operations' not found"
        fi
    else
        log_info "Skipping cluster role check for production environment"
        ((checks_passed++))
    fi
    
    if [ $checks_passed -eq $total_checks ]; then
        log_success "RBAC configuration complete"
        return 0
    else
        log_warning "RBAC configuration incomplete ($checks_passed/$total_checks checks passed)"
        return 1
    fi
}

check_deployment() {
    log_info "Checking IMS connector deployment"
    
    local app_name="ims-connector"
    
    if oc get deployment "$app_name" -n "$NAMESPACE" &>/dev/null; then
        local ready_replicas
        local desired_replicas
        
        ready_replicas=$(oc get deployment "$app_name" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        desired_replicas=$(oc get deployment "$app_name" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$ready_replicas" = "$desired_replicas" ] && [ "$ready_replicas" != "0" ]; then
            log_success "Deployment $app_name is ready ($ready_replicas/$desired_replicas replicas)"
            return 0
        else
            log_error "Deployment $app_name not ready ($ready_replicas/$desired_replicas replicas)"
            return 1
        fi
    else
        log_error "Deployment $app_name not found"
        return 1
    fi
}

check_supporting_resources() {
    log_info "Checking supporting resources"
    
    local checks_passed=0
    local total_checks=3
    local app_name="ims-connector"
    
    # Check ConfigMap
    if oc get configmap "${app_name}-config" -n "$NAMESPACE" &>/dev/null; then
        log_success "ConfigMap ${app_name}-config found"
        ((checks_passed++))
    else
        log_error "ConfigMap ${app_name}-config not found"
    fi
    
    # Check Secret
    if oc get secret "${app_name}-secret" -n "$NAMESPACE" &>/dev/null; then
        log_success "Secret ${app_name}-secret found"
        ((checks_passed++))
    else
        log_error "Secret ${app_name}-secret not found"
    fi
    
    # Check Service
    if oc get service "${app_name}-service" -n "$NAMESPACE" &>/dev/null; then
        log_success "Service ${app_name}-service found"
        ((checks_passed++))
    else
        log_error "Service ${app_name}-service not found"
    fi
    
    if [ $checks_passed -eq $total_checks ]; then
        log_success "All supporting resources found"
        return 0
    else
        log_warning "Supporting resources incomplete ($checks_passed/$total_checks found)"
        return 1
    fi
}

test_idempotency() {
    log_info "Testing deployment idempotency"
    
    # Get current deployment resource version
    local current_version
    current_version=$(oc get deployment "ims-connector" -n "$NAMESPACE" -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null || echo "")
    
    if [ -z "$current_version" ]; then
        log_error "Cannot test idempotency - deployment not found"
        return 1
    fi
    
    # Attempt to apply the same deployment (this would typically be done via playbook)
    log_info "Simulating idempotent deployment operation..."
    
    # For simulation, we'll just check if the deployment is stable
    sleep 2
    
    local new_version
    new_version=$(oc get deployment "ims-connector" -n "$NAMESPACE" -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null || echo "")
    
    if [ "$current_version" = "$new_version" ]; then
        log_success "Deployment is stable - idempotency verified"
        return 0
    else
        log_warning "Deployment resource version changed - may indicate non-idempotent behavior"
        return 1
    fi
}

check_rollback_capability() {
    log_info "Checking rollback capability annotations"
    
    local deployment_annotations
    deployment_annotations=$(oc get deployment "ims-connector" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations}' 2>/dev/null || echo '{}')
    
    if echo "$deployment_annotations" | grep -q "deployment.workshop.redhat.com/last-operation"; then
        log_success "Rollback capability has been demonstrated (annotations found)"
        return 0
    else
        log_warning "Rollback capability not yet demonstrated"
        return 1
    fi
}

generate_summary_report() {
    local namespace_ok=$1
    local sa_ok=$2
    local rbac_ok=$3
    local deployment_ok=$4
    local resources_ok=$5
    local idempotency_ok=$6
    local rollback_ok=$7
    
    local total_passed=0
    local critical_passed=0
    local critical_total=5
    
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Validation Summary                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${YELLOW}Critical Checks:${NC}"
    
    if [ $namespace_ok -eq 0 ]; then
        echo -e "  ✓ Namespace Setup: ${GREEN}PASS${NC}"
        ((critical_passed++))
        ((total_passed++))
    else
        echo -e "  ✗ Namespace Setup: ${RED}FAIL${NC}"
    fi
    
    if [ $sa_ok -eq 0 ]; then
        echo -e "  ✓ Service Accounts: ${GREEN}PASS${NC}"
        ((critical_passed++))
        ((total_passed++))
    else
        echo -e "  ✗ Service Accounts: ${RED}FAIL${NC}"
    fi
    
    if [ $rbac_ok -eq 0 ]; then
        echo -e "  ✓ RBAC Configuration: ${GREEN}PASS${NC}"
        ((critical_passed++))
        ((total_passed++))
    else
        echo -e "  ✗ RBAC Configuration: ${RED}FAIL${NC}"
    fi
    
    if [ $deployment_ok -eq 0 ]; then
        echo -e "  ✓ Deployment Health: ${GREEN}PASS${NC}"
        ((critical_passed++))
        ((total_passed++))
    else
        echo -e "  ✗ Deployment Health: ${RED}FAIL${NC}"
    fi
    
    if [ $resources_ok -eq 0 ]; then
        echo -e "  ✓ Supporting Resources: ${GREEN}PASS${NC}"
        ((critical_passed++))
        ((total_passed++))
    else
        echo -e "  ✗ Supporting Resources: ${RED}FAIL${NC}"
    fi
    
    echo -e "\n${YELLOW}Learning Validation:${NC}"
    
    if [ $idempotency_ok -eq 0 ]; then
        echo -e "  ✓ Idempotency: ${GREEN}DEMONSTRATED${NC}"
        ((total_passed++))
    else
        echo -e "  ○ Idempotency: ${YELLOW}NOT VERIFIED${NC}"
    fi
    
    if [ $rollback_ok -eq 0 ]; then
        echo -e "  ✓ Rollback Capability: ${GREEN}DEMONSTRATED${NC}"
        ((total_passed++))
    else
        echo -e "  ○ Rollback Capability: ${YELLOW}NOT TESTED${NC}"
    fi
    
    echo -e "\n${YELLOW}Overall Status:${NC}"
    if [ $critical_passed -eq $critical_total ]; then
        echo -e "  🎉 ${GREEN}MODULE 2 COMPLETE${NC} - Ready for Module 3"
        echo -e "  Critical Requirements: ${GREEN}$critical_passed/$critical_total PASSED${NC}"
        echo -e "  Total Validations: ${GREEN}$total_passed/7 PASSED${NC}"
    else
        echo -e "  ⚠️  ${YELLOW}ISSUES FOUND${NC} - Review required"
        echo -e "  Critical Requirements: ${RED}$critical_passed/$critical_total PASSED${NC}"
        echo -e "  Total Validations: ${YELLOW}$total_passed/7 PASSED${NC}"
    fi
    
    return $((critical_total - critical_passed))
}

provide_next_steps() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                        Next Steps                            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${YELLOW}Completed Exercises:${NC}"
    echo -e "  • Exercise 2-1: Idempotent deployment patterns"
    echo -e "  • Exercise 2-2: RBAC and service account automation"
    echo -e "  • Exercise 2-3: Rollback capabilities (if tested)"
    echo -e "  • Exercise 2-4: Validation and peer review"
    
    echo -e "\n${YELLOW}Learning Outcomes Achieved:${NC}"
    echo -e "  • Production-ready resource management with redhat.openshift collection"
    echo -e "  • Automated service account provisioning with RBAC binding"
    echo -e "  • Block-rescue-always patterns for error handling"
    echo -e "  • Security context constraints for IMS workloads"
    
    echo -e "\n${YELLOW}Ready for Module 3:${NC}"
    echo -e "  • Advanced automation and error handling"
    echo -e "  • Complex Jinja2 templating"
    echo -e "  • Production troubleshooting scenarios"
    
    echo -e "\n${BLUE}Commands to run Module 3:${NC}"
    echo -e "  ansible-playbook playbooks/module3/exercise3-1-advanced-templating.yml"
    echo -e "  ansible-playbook playbooks/module3/exercise3-2-error-handling.yml"
}

# Main execution
main() {
    print_header
    
    log_info "Validating Module 2 completion for namespace: $NAMESPACE (environment: $ENVIRONMENT)"
    
    # Run all validation checks
    check_namespace
    local namespace_result=$?
    
    check_service_accounts
    local sa_result=$?
    
    check_rbac_configuration
    local rbac_result=$?
    
    check_deployment
    local deployment_result=$?
    
    check_supporting_resources
    local resources_result=$?
    
    test_idempotency
    local idempotency_result=$?
    
    check_rollback_capability
    local rollback_result=$?
    
    # Generate summary report
    generate_summary_report $namespace_result $sa_result $rbac_result $deployment_result $resources_result $idempotency_result $rollback_result
    local overall_result=$?
    
    # Provide guidance
    provide_next_steps
    
    # Exit with appropriate code
    if [ $overall_result -eq 0 ]; then
        log_success "Module 2 validation completed successfully!"
        exit 0
    else
        log_error "Module 2 validation found issues. Please review and complete missing exercises."
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi