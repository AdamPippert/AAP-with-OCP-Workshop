#!/bin/bash

# Multi-User Workshop Validation Script
# Validates all user environments are properly configured

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
USER_ENV_DIR="${REPO_ROOT}/user_environments"
VALIDATION_SCRIPT="${SCRIPT_DIR}/exercise0/validate_setup.sh"
LOG_DIR="${USER_ENV_DIR}/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

usage() {
    cat << EOF
Multi-User Workshop Validation

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -d, --directory DIR     User environments directory (default: user_environments)
    -u, --users RANGE       User range (e.g., 1-5, 3,7,9, or single number)
    --quick                 Quick validation (basic connectivity only)
    --full                  Full validation (all components)
    --fix                   Attempt to fix common issues
    -v, --verbose           Verbose output
    -h, --help              Show this help

DESCRIPTION:
    This script validates that all user workshop environments are properly
    configured and accessible. It checks:
    
    - Environment file validity
    - OpenShift connectivity
    - AAP Controller accessibility
    - Execution environment availability
    - Workshop resources (namespaces, projects, etc.)

EXAMPLES:
    $0                                  # Validate all users (quick)
    $0 --full                          # Full validation for all users
    $0 -u 1-5 --full                   # Full validation for users 1-5
    $0 --fix                           # Attempt to fix issues found

OUTPUT:
    user_environments/logs/
    ├── validation_user01.log          # Individual validation logs
    ├── validation_user02.log
    ├── ...
    └── validation_summary.txt         # Overall validation report

EOF
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    if [[ ! -d "${USER_ENV_DIR}" ]]; then
        error "User environments directory not found: ${USER_ENV_DIR}"
        exit 1
    fi
    
    # Check for .env files
    local env_files
    env_files=$(find "${USER_ENV_DIR}" -name ".env[0-9][0-9]" -type f | wc -l)
    if [[ "${env_files}" -eq 0 ]]; then
        error "No user environment files found in ${USER_ENV_DIR}"
        exit 1
    fi
    
    success "Found ${env_files} user environment(s)"
}

create_log_directory() {
    mkdir -p "${LOG_DIR}"
}

validate_env_file() {
    local env_file="$1"
    local user_num="$2"
    
    local issues=()
    
    # Check if file exists and is readable
    if [[ ! -f "${env_file}" ]]; then
        issues+=("Environment file not found")
        return 1
    fi
    
    if [[ ! -r "${env_file}" ]]; then
        issues+=("Environment file not readable")
        return 1
    fi
    
    # Source the file and check required variables
    source "${env_file}"
    
    local required_vars=(
        "USER_EMAIL"
        "AAP_URL"
        "AAP_USERNAME"
        "AAP_PASSWORD"
        "OCP_CONSOLE_URL"
        "OCP_API_URL"
        "OCP_CLUSTER_DOMAIN"
        "WORKSHOP_GUID"
        "SSH_HOST"
        "SSH_PORT"
        "SSH_USER"
        "SSH_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            issues+=("Missing required variable: ${var}")
        fi
    done
    
    # Check URL formats
    if [[ -n "${AAP_URL:-}" && ! "${AAP_URL}" =~ ^https?:// ]]; then
        issues+=("AAP_URL should start with http:// or https://")
    fi
    
    if [[ -n "${OCP_CONSOLE_URL:-}" && ! "${OCP_CONSOLE_URL}" =~ ^https?:// ]]; then
        issues+=("OCP_CONSOLE_URL should start with http:// or https://")
    fi
    
    if [[ -n "${OCP_API_URL:-}" && ! "${OCP_API_URL}" =~ ^https?:// ]]; then
        issues+=("OCP_API_URL should start with http:// or https://")
    fi
    
    # Check port is numeric
    if [[ -n "${SSH_PORT:-}" && ! "${SSH_PORT}" =~ ^[0-9]+$ ]]; then
        issues+=("SSH_PORT should be numeric")
    fi
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf '%s\n' "${issues[@]}"
        return 1
    fi
    
    return 0
}

test_connectivity() {
    local env_file="$1"
    local user_num="$2"
    local test_type="$3"  # quick or full
    
    source "${env_file}"
    
    local results=()
    local issues=()
    
    # Test AAP Controller connectivity
    log "Testing AAP Controller connectivity for user ${user_num}..."
    if curl -k -s --connect-timeout 10 "${AAP_URL}/api/v2/ping/" >/dev/null 2>&1; then
        results+=("AAP_CONNECTIVITY: PASS")
    else
        results+=("AAP_CONNECTIVITY: FAIL")
        issues+=("Cannot reach AAP Controller at ${AAP_URL}")
    fi
    
    # Test AAP authentication
    if [[ -n "${AAP_USERNAME:-}" && -n "${AAP_PASSWORD:-}" ]]; then
        log "Testing AAP authentication for user ${user_num}..."
        local auth_test
        auth_test=$(curl -k -s --connect-timeout 10 \
            -H "Authorization: Basic $(echo -n "${AAP_USERNAME}:${AAP_PASSWORD}" | base64)" \
            "${AAP_URL}/api/controller/v2/me/" 2>/dev/null | grep -o '"id":[0-9]*' || echo "")
        
        if [[ -n "${auth_test}" ]]; then
            results+=("AAP_AUTH: PASS")
        else
            results+=("AAP_AUTH: FAIL")
            issues+=("AAP authentication failed with provided credentials")
        fi
    fi
    
    # Test SSH connectivity (if requested for full test)
    if [[ "${test_type}" == "full" && -n "${SSH_HOST:-}" && -n "${SSH_PORT:-}" ]]; then
        log "Testing SSH connectivity for user ${user_num}..."
        if timeout 10 nc -z "${SSH_HOST}" "${SSH_PORT}" >/dev/null 2>&1; then
            results+=("SSH_CONNECTIVITY: PASS")
        else
            results+=("SSH_CONNECTIVITY: FAIL")
            issues+=("Cannot reach SSH bastion at ${SSH_HOST}:${SSH_PORT}")
        fi
    fi
    
    # Test OpenShift API connectivity
    if [[ -n "${OCP_API_URL:-}" ]]; then
        log "Testing OpenShift API connectivity for user ${user_num}..."
        if curl -k -s --connect-timeout 10 "${OCP_API_URL}/version" >/dev/null 2>&1; then
            results+=("OCP_API_CONNECTIVITY: PASS")
        else
            results+=("OCP_API_CONNECTIVITY: FAIL")
            issues+=("Cannot reach OpenShift API at ${OCP_API_URL}")
        fi
    fi
    
    # Test cluster domain resolution
    if [[ -n "${OCP_CLUSTER_DOMAIN:-}" ]]; then
        log "Testing cluster domain resolution for user ${user_num}..."
        if nslookup "console-openshift-console.${OCP_CLUSTER_DOMAIN}" >/dev/null 2>&1; then
            results+=("CLUSTER_DNS: PASS")
        else
            results+=("CLUSTER_DNS: FAIL")
            issues+=("Cannot resolve cluster domain: ${OCP_CLUSTER_DOMAIN}")
        fi
    fi
    
    # Return results
    printf '%s\n' "${results[@]}"
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf 'ISSUE: %s\n' "${issues[@]}"
        return 1
    fi
    
    return 0
}

validate_workshop_resources() {
    local env_file="$1"
    local user_num="$2"
    
    source "${env_file}"
    
    local results=()
    local issues=()
    
    # Check if bearer token is available for OpenShift operations
    if [[ -z "${OCP_BEARER_TOKEN:-}" ]]; then
        results+=("OCP_TOKEN: MISSING")
        issues+=("OpenShift bearer token not configured - some checks skipped")
        printf '%s\n' "${results[@]}"
        printf 'ISSUE: %s\n' "${issues[@]}"
        return 1
    fi
    
    # Test OpenShift authentication
    log "Testing OpenShift authentication for user ${user_num}..."
    local oc_test
    oc_test=$(curl -k -s --connect-timeout 10 \
        -H "Authorization: Bearer ${OCP_BEARER_TOKEN}" \
        "${OCP_API_URL}/api/v1/namespaces" 2>/dev/null | grep -o '"kind":"NamespaceList"' || echo "")
    
    if [[ -n "${oc_test}" ]]; then
        results+=("OCP_AUTH: PASS")
        
        # Check for workshop namespace
        local ns_test
        ns_test=$(curl -k -s --connect-timeout 10 \
            -H "Authorization: Bearer ${OCP_BEARER_TOKEN}" \
            "${OCP_API_URL}/api/v1/namespaces/workshop-aap" 2>/dev/null | grep -o '"name":"workshop-aap"' || echo "")
        
        if [[ -n "${ns_test}" ]]; then
            results+=("WORKSHOP_NAMESPACE: PASS")
        else
            results+=("WORKSHOP_NAMESPACE: FAIL")
            issues+=("Workshop namespace 'workshop-aap' not found")
        fi
        
    else
        results+=("OCP_AUTH: FAIL")
        issues+=("OpenShift authentication failed with provided token")
    fi
    
    # Check AAP resources if we have AAP access
    if curl -k -s --connect-timeout 10 "${AAP_URL}/api/v2/ping/" >/dev/null 2>&1; then
        log "Checking AAP workshop resources for user ${user_num}..."
        
        local auth_header="Authorization: Basic $(echo -n "${AAP_USERNAME}:${AAP_PASSWORD}" | base64)"
        
        # Check for project
        local project_test
        project_test=$(curl -k -s --connect-timeout 10 \
            -H "${auth_header}" \
            "${AAP_URL}/api/controller/v2/projects/?name=AAP-Workshop-${WORKSHOP_GUID}" 2>/dev/null | grep -o '"count":[0-9]*' | cut -d: -f2 || echo "0")
        
        if [[ "${project_test}" -gt 0 ]]; then
            results+=("AAP_PROJECT: PASS")
        else
            results+=("AAP_PROJECT: FAIL")
            issues+=("AAP project 'AAP-Workshop-${WORKSHOP_GUID}' not found")
        fi
        
        # Check for execution environment
        local ee_test
        ee_test=$(curl -k -s --connect-timeout 10 \
            -H "${auth_header}" \
            "${AAP_URL}/api/controller/v2/execution_environments/?name=Workshop-EE-${WORKSHOP_GUID}" 2>/dev/null | grep -o '"count":[0-9]*' | cut -d: -f2 || echo "0")
        
        if [[ "${ee_test}" -gt 0 ]]; then
            results+=("AAP_EXECUTION_ENV: PASS")
        else
            results+=("AAP_EXECUTION_ENV: FAIL")
            issues+=("AAP execution environment 'Workshop-EE-${WORKSHOP_GUID}' not found")
        fi
    fi
    
    printf '%s\n' "${results[@]}"
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf 'ISSUE: %s\n' "${issues[@]}"
        return 1
    fi
    
    return 0
}

validate_user() {
    local user_num="$1"
    local test_type="$2"
    local fix_mode="$3"
    local verbose="$4"
    
    local env_file="${USER_ENV_DIR}/.env${user_num}"
    local log_file="${LOG_DIR}/validation_user${user_num}.log"
    
    if [[ "${verbose}" == "true" ]]; then
        log "Validating user ${user_num}..."
    fi
    
    local validation_results=()
    local all_passed=true
    
    # Redirect output to log file
    {
        echo "=== User ${user_num} Validation Report ==="
        echo "Generated: $(date)"
        echo "Environment File: ${env_file}"
        echo
        
        # 1. Validate environment file
        echo "1. Environment File Validation"
        echo "=============================="
        if validate_env_file "${env_file}" "${user_num}"; then
            echo "PASS: Environment file is valid"
            validation_results+=("ENV_FILE: PASS")
        else
            echo "FAIL: Environment file validation failed:"
            validate_env_file "${env_file}" "${user_num}" | sed 's/^/  /'
            validation_results+=("ENV_FILE: FAIL")
            all_passed=false
        fi
        echo
        
        # 2. Test connectivity
        echo "2. Connectivity Tests"
        echo "===================="
        if test_connectivity "${env_file}" "${user_num}" "${test_type}"; then
            echo "PASS: All connectivity tests passed"
            test_connectivity "${env_file}" "${user_num}" "${test_type}" | sed 's/^/  /'
        else
            echo "FAIL: Some connectivity tests failed:"
            test_connectivity "${env_file}" "${user_num}" "${test_type}" | sed 's/^/  /'
            all_passed=false
        fi
        echo
        
        # 3. Workshop resources (full test only)
        if [[ "${test_type}" == "full" ]]; then
            echo "3. Workshop Resources"
            echo "==================="
            if validate_workshop_resources "${env_file}" "${user_num}"; then
                echo "PASS: All workshop resources are configured"
                validate_workshop_resources "${env_file}" "${user_num}" | sed 's/^/  /'
            else
                echo "FAIL: Some workshop resources missing:"
                validate_workshop_resources "${env_file}" "${user_num}" | sed 's/^/  /'
                all_passed=false
            fi
            echo
        fi
        
        # Summary
        echo "=== Validation Summary ==="
        if [[ "${all_passed}" == "true" ]]; then
            echo "OVERALL: PASS - User ${user_num} environment is ready"
        else
            echo "OVERALL: FAIL - User ${user_num} environment has issues"
        fi
        
    } > "${log_file}" 2>&1
    
    if [[ "${all_passed}" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

generate_validation_summary() {
    local users=("$@")
    local summary_file="${LOG_DIR}/validation_summary.txt"
    
    log "Generating validation summary..."
    
    local total_users=${#users[@]}
    local passed=0
    local failed=0
    
    # Count results
    for user in "${users[@]}"; do
        local log_file="${LOG_DIR}/validation_user${user}.log"
        if [[ -f "${log_file}" ]]; then
            if grep -q "OVERALL: PASS" "${log_file}"; then
                ((passed++))
            else
                ((failed++))
            fi
        else
            ((failed++))
        fi
    done
    
    # Generate summary
    cat << EOF > "${summary_file}"
Multi-User Workshop Validation Summary
Generated on: $(date)

Total Users Validated: ${total_users}
Passed: ${passed}
Failed: ${failed}

User Results:
EOF
    
    # Add individual user results
    for user in "${users[@]}"; do
        local log_file="${LOG_DIR}/validation_user${user}.log"
        local env_file="${USER_ENV_DIR}/.env${user}"
        local email=""
        
        if [[ -f "${env_file}" ]]; then
            email=$(grep "USER_EMAIL=" "${env_file}" | cut -d'=' -f2)
        fi
        
        local result="UNKNOWN"
        if [[ -f "${log_file}" ]]; then
            if grep -q "OVERALL: PASS" "${log_file}"; then
                result="PASS"
            else
                result="FAIL"
            fi
        else
            result="NOT_TESTED"
        fi
        
        printf "  User %s: %-10s %s\n" "${user}" "${result}" "${email}" >> "${summary_file}"
    done
    
    cat << EOF >> "${summary_file}"

Failed Validations (if any):
$(for user in "${users[@]}"; do
    log_file="${LOG_DIR}/validation_user${user}.log"
    if [[ -f "${log_file}" && $(grep -q "OVERALL: FAIL" "${log_file}"; echo $?) -eq 0 ]]; then
        echo "  User ${user}: See validation_user${user}.log for details"
    fi
done)

Common Issues Found:
$(for user in "${users[@]}"; do
    log_file="${LOG_DIR}/validation_user${user}.log"
    if [[ -f "${log_file}" ]]; then
        grep "ISSUE:" "${log_file}" | sed 's/ISSUE: //' | sort | uniq
    fi
done | sort | uniq -c | sort -nr | head -5)

Next Steps:
- Review individual validation logs for detailed issues
- Fix common configuration problems
- Re-run validation after fixes
- Contact workshop support for persistent issues
EOF
    
    success "Validation summary written to: ${summary_file}"
    
    # Display brief summary
    echo
    echo "=================================="
    echo "  MULTI-USER VALIDATION SUMMARY"
    echo "=================================="
    echo "Total Users:  ${total_users}"
    echo "Passed:       ${passed}"
    echo "Failed:       ${failed}"
    echo
    
    if [[ ${failed} -gt 0 ]]; then
        warning "Some validations failed. Check individual logs for details."
        return 1
    else
        success "All user environments validated successfully!"
        return 0
    fi
}

parse_user_range() {
    local range="$1"
    local users=()
    
    if [[ "${range}" =~ ^[0-9]+-[0-9]+$ ]]; then
        # Range format: 1-10
        local start end
        start=$(echo "${range}" | cut -d'-' -f1)
        end=$(echo "${range}" | cut -d'-' -f2)
        
        for ((i=start; i<=end; i++)); do
            users+=("$(printf "%02d" $i)")
        done
        
    elif [[ "${range}" =~ ^[0-9,]+$ ]]; then
        # Comma-separated format: 1,3,5,7
        IFS=',' read -ra user_list <<< "${range}"
        for user in "${user_list[@]}"; do
            users+=("$(printf "%02d" $user)")
        done
        
    elif [[ "${range}" =~ ^[0-9]+$ ]]; then
        # Single user: 5
        users+=("$(printf "%02d" $range)")
        
    else
        error "Invalid user range format: ${range}"
        error "Use formats like: 1-10, 1,3,5, or 5"
        exit 1
    fi
    
    printf '%s\n' "${users[@]}"
}

main() {
    local user_env_dir="${USER_ENV_DIR}"
    local user_range=""
    local test_type="quick"
    local fix_mode="false"
    local verbose="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--directory)
                user_env_dir="$2"
                shift 2
                ;;
            -u|--users)
                user_range="$2"
                shift 2
                ;;
            --quick)
                test_type="quick"
                shift
                ;;
            --full)
                test_type="full"
                shift
                ;;
            --fix)
                fix_mode="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Update global variables
    USER_ENV_DIR="${user_env_dir}"
    LOG_DIR="${USER_ENV_DIR}/logs"
    
    # Run validation
    check_prerequisites
    create_log_directory
    
    # Get list of users to validate
    local users=()
    if [[ -n "${user_range}" ]]; then
        local user_list
        user_list=$(parse_user_range "${user_range}")
        while IFS= read -r line; do
            [[ -n "$line" ]] && users+=("$line")
        done <<< "$user_list"
    else
        local user_list
        user_list=$(find "${USER_ENV_DIR}" -name ".env[0-9][0-9]" -type f | \
                   sed 's/.*\.env\([0-9][0-9]\)/\1/' | sort)
        while IFS= read -r line; do
            [[ -n "$line" ]] && users+=("$line")
        done <<< "$user_list"
    fi
    
    if [[ ${#users[@]} -eq 0 ]]; then
        error "No users found to validate"
        exit 1
    fi
    
    log "Validating ${#users[@]} user environment(s) (${test_type} mode)"
    
    # Run validations
    local failed_count=0
    for user in "${users[@]}"; do
        if ! validate_user "${user}" "${test_type}" "${fix_mode}" "${verbose}"; then
            ((failed_count++))
        fi
    done
    
    # Generate summary
    if generate_validation_summary "${users[@]}"; then
        exit 0
    else
        exit 1
    fi
}

main "$@"