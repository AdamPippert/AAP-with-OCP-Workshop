#!/bin/bash

# Exercise 0: Workshop Environment Validation
# Validates that the workshop environment is properly configured

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VALIDATION_PASSED=0
VALIDATION_FAILED=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
    ((VALIDATION_PASSED++))
}

warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

failure() {
    echo -e "${RED}✗${NC} $*"
    ((VALIDATION_FAILED++))
}

validate_prerequisites() {
    log "Validating prerequisites..."
    
    if command -v oc >/dev/null 2>&1; then
        success "OpenShift CLI (oc) is installed"
    else
        failure "OpenShift CLI (oc) not found"
    fi
    
    if command -v ansible-playbook >/dev/null 2>&1; then
        success "Ansible is installed"
        local ansible_version=$(ansible --version | head -1)
        log "  ${ansible_version}"
    else
        failure "Ansible not found"
    fi
    
    if [[ -f "${ENV_FILE}" ]]; then
        success "Environment file (.env) exists"
    else
        failure "Environment file (.env) not found - run setup_workshop.sh first"
        return 1
    fi
}

validate_openshift_connectivity() {
    log "Validating OpenShift connectivity..."
    
    if oc whoami >/dev/null 2>&1; then
        local current_user=$(oc whoami)
        success "Connected to OpenShift as: ${current_user}"
        
        local cluster_info=$(oc cluster-info | head -1)
        log "  ${cluster_info}"
    else
        failure "Not connected to OpenShift cluster"
        warning "Please run: oc login <cluster-url>"
        return 1
    fi
}

validate_workshop_namespaces() {
    log "Validating workshop namespaces..."
    
    local namespaces=("workshop-aap" "workshop-aap-dev" "workshop-aap-test" "workshop-aap-prod")
    
    for ns in "${namespaces[@]}"; do
        if oc get namespace "${ns}" >/dev/null 2>&1; then
            success "Namespace ${ns} exists"
        else
            failure "Namespace ${ns} not found"
        fi
    done
}

validate_service_account() {
    log "Validating workshop service account..."
    
    if oc get serviceaccount workshop-automation -n workshop-aap >/dev/null 2>&1; then
        success "Service account 'workshop-automation' exists"
    else
        failure "Service account 'workshop-automation' not found"
    fi
    
    if oc get clusterrolebinding workshop-automation-binding >/dev/null 2>&1; then
        success "Cluster role binding exists"
    else
        failure "Cluster role binding 'workshop-automation-binding' not found"
    fi
}

validate_resource_quotas() {
    log "Validating resource quotas..."
    
    local environments=("dev" "test" "prod")
    
    for env in "${environments[@]}"; do
        local quota_name="${env}-quota"
        local namespace="workshop-aap-${env}"
        
        if oc get resourcequota "${quota_name}" -n "${namespace}" >/dev/null 2>&1; then
            success "Resource quota for ${env} environment exists"
            
            # Show quota status
            local quota_status=$(oc get resourcequota "${quota_name}" -n "${namespace}" -o jsonpath='{.status.used}' 2>/dev/null || echo "{}")
            if [[ "${quota_status}" != "{}" ]]; then
                log "  Current usage: ${quota_status}"
            fi
        else
            failure "Resource quota for ${env} environment not found"
        fi
    done
}

validate_network_policies() {
    log "Validating network policies..."
    
    local environments=("dev" "test" "prod")
    
    for env in "${environments[@]}"; do
        local policy_name="${env}-isolation"
        local namespace="workshop-aap-${env}"
        
        if oc get networkpolicy "${policy_name}" -n "${namespace}" >/dev/null 2>&1; then
            success "Network policy for ${env} environment exists"
        else
            failure "Network policy for ${env} environment not found"
        fi
    done
}

validate_aap_connectivity() {
    log "Validating Automation Controller connectivity..."
    
    if [[ -f "${ENV_FILE}" ]]; then
        source "${ENV_FILE}"
        
        if [[ -n "${AAP_URL:-}" ]]; then
            if curl -k -s --connect-timeout 10 "${AAP_URL}/api/v2/ping/" >/dev/null; then
                success "Automation Controller is accessible at ${AAP_URL}"
            else
                warning "Cannot reach Automation Controller at ${AAP_URL}"
                log "  This may be expected if AAP is not yet configured"
            fi
        else
            warning "AAP_URL not found in environment file"
        fi
    fi
}

validate_workshop_config() {
    log "Validating workshop configuration..."
    
    if oc get configmap workshop-config -n workshop-aap >/dev/null 2>&1; then
        success "Workshop configuration ConfigMap exists"
        
        local workshop_name=$(oc get configmap workshop-config -n workshop-aap -o jsonpath='{.data.workshop_name}' 2>/dev/null)
        if [[ -n "${workshop_name}" ]]; then
            log "  Workshop: ${workshop_name}"
        fi
        
        local environments=$(oc get configmap workshop-config -n workshop-aap -o jsonpath='{.data.environments}' 2>/dev/null)
        if [[ -n "${environments}" ]]; then
            log "  Environments: ${environments}"
        fi
    else
        failure "Workshop configuration ConfigMap not found"
    fi
}

generate_summary() {
    log "Validation Summary"
    echo "=================="
    echo -e "${GREEN}Passed:${NC} ${VALIDATION_PASSED}"
    echo -e "${RED}Failed:${NC} ${VALIDATION_FAILED}"
    echo
    
    if [[ ${VALIDATION_FAILED} -eq 0 ]]; then
        success "All validations passed! Workshop environment is ready."
        echo
        log "Next steps:"
        log "  1. Proceed to Module 1: Dynamic Inventory and AAP Integration"
        log "  2. Run: ansible-playbook playbooks/module1/exercise1-1-test-inventory.yml"
        return 0
    else
        failure "Some validations failed. Please review and fix the issues above."
        echo
        log "To fix issues:"
        log "  1. Re-run the setup: ./scripts/exercise0/setup_workshop.sh"
        log "  2. Run the setup playbook: ansible-playbook playbooks/exercise0/setup.yml"
        log "  3. Validate again: ./scripts/exercise0/validate_setup.sh"
        return 1
    fi
}

main() {
    log "Starting Exercise 0: Workshop Environment Validation"
    echo
    
    validate_prerequisites || true
    validate_openshift_connectivity || true
    validate_workshop_namespaces || true
    validate_service_account || true
    validate_resource_quotas || true
    validate_network_policies || true
    validate_aap_connectivity || true
    validate_workshop_config || true
    
    echo
    generate_summary
}

main "$@"