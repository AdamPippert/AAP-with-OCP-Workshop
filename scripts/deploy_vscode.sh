#!/bin/bash

# VSCode Server Deployment Script for AAP Workshop
# Deploys VSCode server instances for workshop users

set -euo pipefail

# Default configuration
DEFAULT_NAMESPACE="workshop-vscode"
DEFAULT_ENV_DIR="user_environments"
DEFAULT_PARALLEL=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests/vscode-server"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage information
usage() {
    cat << EOF
VSCode Server Deployment for AAP Workshop

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -d, --directory DIR     User environments directory (default: user_environments)
    -u, --users RANGE       User range (e.g., 1-5, 3,7,9, or single number)
    -p, --parallel NUM      Max parallel deployments (default: 5)
    -n, --namespace NAME    VSCode namespace (default: workshop-vscode)
    --deploy                Deploy VSCode instances (default action)
    --undeploy              Remove VSCode instances
    --status                Check deployment status
    --dry-run               Preview without executing
    -v, --verbose           Detailed output
    -h, --help              Show this help

EXAMPLES:
    $0                          # Deploy VSCode for all users
    $0 -u 1-10                  # Deploy for users 1-10
    $0 --undeploy -u 5          # Remove VSCode for user 5
    $0 --status                 # Check all deployments
    $0 --dry-run -v             # Preview deployment

USER RANGE FORMATS:
    5           Single user
    1-10        Range of users  
    1,3,5       Specific users
    1-5,8-12    Multiple ranges

EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

# Parse user range into array
parse_user_range() {
    local range="$1"
    local users=()
    
    if [[ $range =~ ^[0-9]+$ ]]; then
        # Single user
        users=("$range")
    elif [[ $range =~ ^[0-9]+-[0-9]+$ ]]; then
        # Range: 1-10
        local start=$(echo "$range" | cut -d'-' -f1)
        local end=$(echo "$range" | cut -d'-' -f2)
        for ((i=start; i<=end; i++)); do
            users+=("$i")
        done
    elif [[ $range =~ , ]]; then
        # Comma-separated or complex ranges
        IFS=',' read -ra PARTS <<< "$range"
        for part in "${PARTS[@]}"; do
            if [[ $part =~ ^[0-9]+$ ]]; then
                users+=("$part")
            elif [[ $part =~ ^[0-9]+-[0-9]+$ ]]; then
                local start=$(echo "$part" | cut -d'-' -f1)
                local end=$(echo "$part" | cut -d'-' -f2)
                for ((i=start; i<=end; i++)); do
                    users+=("$i")
                done
            fi
        done
    else
        log_error "Invalid user range format: $range"
        return 1
    fi
    
    # Sort and deduplicate
    printf '%s\n' "${users[@]}" | sort -n | uniq
}

# Check if OpenShift CLI is available and user is logged in
check_oc_login() {
    if ! command -v oc &> /dev/null; then
        log_error "OpenShift CLI 'oc' not found. Please install it."
        return 1
    fi
    
    if ! oc whoami &> /dev/null; then
        log_error "Not logged into OpenShift. Please run 'oc login'."
        return 1
    fi
    
    local current_user
    current_user=$(oc whoami)
    log_info "Logged in as: $current_user"
}

# Load user environment configuration
load_user_env() {
    local user_num="$1"
    local env_dir="$2"
    local env_file="${env_dir}/.env$(printf "%02d" "$user_num")"
    
    if [[ ! -f "$env_file" ]]; then
        log_error "Environment file not found: $env_file"
        return 1
    fi
    
    # Source the environment file
    set -a  # automatically export all variables
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
    
    # Validate required variables
    local required_vars=("USER_EMAIL" "OCP_CLUSTER_DOMAIN" "AAP_URL" "WORKSHOP_GUID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var not found in $env_file"
            return 1
        fi
    done
}

# Deploy namespace and common resources
deploy_namespace() {
    local namespace="$1"
    local verbose="$2"
    
    log_info "Deploying VSCode namespace and common resources..."
    
    if [[ "$verbose" == "true" ]]; then
        oc apply -f "${MANIFESTS_DIR}/namespace.yaml"
        oc apply -f "${MANIFESTS_DIR}/serviceaccount.yaml"
        oc apply -f "${MANIFESTS_DIR}/configmap.yaml"
    else
        oc apply -f "${MANIFESTS_DIR}/namespace.yaml" &> /dev/null
        oc apply -f "${MANIFESTS_DIR}/serviceaccount.yaml" &> /dev/null
        oc apply -f "${MANIFESTS_DIR}/configmap.yaml" &> /dev/null
    fi
    
    log_success "Namespace and common resources deployed"
}

# Deploy VSCode instance for a single user
deploy_user_vscode() {
    local user_num="$1"
    local env_dir="$2"
    local namespace="$3"
    local verbose="$4"
    local dry_run="$5"
    
    local user_num_padded
    user_num_padded=$(printf "%02d" "$user_num")
    
    log_info "Deploying VSCode for user $user_num_padded..."
    
    # Load user environment
    if ! load_user_env "$user_num" "$env_dir"; then
        return 1
    fi
    
    # Set template parameters
    local template_params=(
        "USER_NUMBER=$user_num_padded"
        "USER_EMAIL=$USER_EMAIL"
        "WORKSHOP_GUID=$WORKSHOP_GUID"
        "OCP_CLUSTER_DOMAIN=$OCP_CLUSTER_DOMAIN"
        "AAP_URL=$AAP_URL"
    )
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN: Would deploy VSCode for user $user_num_padded"
        log_info "Parameters: ${template_params[*]}"
        return 0
    fi
    
    # Process and apply template
    local process_args=()
    for param in "${template_params[@]}"; do
        process_args+=("-p" "$param")
    done
    
    if [[ "$verbose" == "true" ]]; then
        oc process -f "${MANIFESTS_DIR}/deployment-template.yaml" "${process_args[@]}" | oc apply -f -
    else
        oc process -f "${MANIFESTS_DIR}/deployment-template.yaml" "${process_args[@]}" | oc apply -f - &> /dev/null
    fi
    
    log_success "VSCode deployed for user $user_num_padded"
    
    # Wait for deployment to be ready (optional)
    if [[ "$verbose" == "true" ]]; then
        log_info "Waiting for deployment to be ready..."
        oc rollout status deployment/vscode-user${user_num_padded} -n "$namespace" --timeout=300s
        
        # Get the route URL
        local route_url
        if route_url=$(oc get route "vscode-user${user_num_padded}" -n "$namespace" -o jsonpath='{.spec.host}' 2>/dev/null); then
            log_success "VSCode available at: https://$route_url"
        fi
    fi
}

# Remove VSCode instance for a single user
undeploy_user_vscode() {
    local user_num="$1"
    local namespace="$2"
    local verbose="$3"
    local dry_run="$4"
    
    local user_num_padded
    user_num_padded=$(printf "%02d" "$user_num")
    
    log_info "Removing VSCode for user $user_num_padded..."
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN: Would remove VSCode for user $user_num_padded"
        return 0
    fi
    
    # Remove user-specific resources
    local resources=(
        "deployment/vscode-user${user_num_padded}"
        "service/vscode-user${user_num_padded}"
        "route/vscode-user${user_num_padded}"
        "secret/vscode-user${user_num_padded}-env"
        "pvc/vscode-user${user_num_padded}-storage"
    )
    
    for resource in "${resources[@]}"; do
        if [[ "$verbose" == "true" ]]; then
            oc delete "$resource" -n "$namespace" --ignore-not-found=true
        else
            oc delete "$resource" -n "$namespace" --ignore-not-found=true &> /dev/null
        fi
    done
    
    log_success "VSCode removed for user $user_num_padded"
}

# Check deployment status for a user
check_user_status() {
    local user_num="$1"
    local namespace="$2"
    
    local user_num_padded
    user_num_padded=$(printf "%02d" "$user_num")
    
    # Check if deployment exists
    if ! oc get deployment "vscode-user${user_num_padded}" -n "$namespace" &> /dev/null; then
        echo "User $user_num_padded: NOT DEPLOYED"
        return 1
    fi
    
    # Check deployment status
    local ready_replicas available_replicas
    ready_replicas=$(oc get deployment "vscode-user${user_num_padded}" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    available_replicas=$(oc get deployment "vscode-user${user_num_padded}" -n "$namespace" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
    
    if [[ "$ready_replicas" == "1" && "$available_replicas" == "1" ]]; then
        # Get route URL
        local route_url
        if route_url=$(oc get route "vscode-user${user_num_padded}" -n "$namespace" -o jsonpath='{.spec.host}' 2>/dev/null); then
            echo "User $user_num_padded: READY - https://$route_url"
        else
            echo "User $user_num_padded: READY (no route)"
        fi
    else
        echo "User $user_num_padded: NOT READY (replicas: $ready_replicas/$available_replicas)"
    fi
}

# Discover all user environment files
discover_users() {
    local env_dir="$1"
    local users=()
    
    for env_file in "$env_dir"/.env[0-9][0-9]; do
        if [[ -f "$env_file" ]]; then
            local user_num
            user_num=$(basename "$env_file" | sed 's/\.env0*//')
            users+=("$user_num")
        fi
    done
    
    if [[ ${#users[@]} -eq 0 ]]; then
        log_error "No user environment files found in $env_dir"
        return 1
    fi
    
    printf '%s\n' "${users[@]}" | sort -n
}

# Parallel deployment function
deploy_users_parallel() {
    local users=("$@")
    local env_dir="$2"
    local namespace="$3"
    local verbose="$4"
    local dry_run="$5"
    local parallel="$6"
    
    # Remove function parameters from users array
    users=("${users[@]:6}")
    
    local pids=()
    local running=0
    local success=0
    local failed=0
    
    for user in "${users[@]}"; do
        # Wait if we've reached the parallel limit
        while [[ $running -ge $parallel ]]; do
            # Check for completed processes
            if [[ ${#pids[@]} -gt 0 ]]; then
                for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    wait "${pids[$i]}"
                    local exit_code=$?
                    if [[ $exit_code -eq 0 ]]; then
                        ((success++))
                    else
                        ((failed++))
                    fi
                    unset 'pids[$i]'
                    ((running--))
                fi
                done
            fi
            sleep 1
        done
        
        # Start new deployment
        deploy_user_vscode "$user" "$env_dir" "$namespace" "$verbose" "$dry_run" &
        pids+=($!)
        ((running++))
    done
    
    # Wait for all remaining processes
    if [[ ${#pids[@]} -gt 0 ]]; then
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                wait "$pid"
                local exit_code=$?
                if [[ $exit_code -eq 0 ]]; then
                    ((success++))
                else
                    ((failed++))
                fi
            fi
        done
    fi
    
    log_info "Deployment complete: $success successful, $failed failed"
    return $failed
}

# Main function
main() {
    local env_dir="$DEFAULT_ENV_DIR"
    local namespace="$DEFAULT_NAMESPACE"
    local parallel="$DEFAULT_PARALLEL"
    local users_range=""
    local action="deploy"
    local verbose="false"
    local dry_run="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--directory)
                env_dir="$2"
                shift 2
                ;;
            -u|--users)
                users_range="$2"
                shift 2
                ;;
            -p|--parallel)
                parallel="$2"
                shift 2
                ;;
            -n|--namespace)
                namespace="$2"
                shift 2
                ;;
            --deploy)
                action="deploy"
                shift
                ;;
            --undeploy)
                action="undeploy"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            --dry-run)
                dry_run="true"
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
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate environment directory
    if [[ ! -d "$env_dir" ]]; then
        log_error "Environment directory not found: $env_dir"
        exit 1
    fi
    
    # Check OpenShift login
    if ! check_oc_login; then
        exit 1
    fi
    
    # Determine users to process
    local users=()
    if [[ -n "$users_range" ]]; then
        local user_list
        user_list=$(parse_user_range "$users_range")
        while IFS= read -r line; do
            [[ -n "$line" ]] && users+=("$line")
        done <<< "$user_list"
    else
        local user_list
        user_list=$(discover_users "$env_dir")
        while IFS= read -r line; do
            [[ -n "$line" ]] && users+=("$line")
        done <<< "$user_list"
    fi
    
    if [[ ${#users[@]} -eq 0 ]]; then
        log_error "No users to process"
        exit 1
    fi
    
    log_info "Processing ${#users[@]} users: ${users[*]}"
    
    # Execute action
    case "$action" in
        deploy)
            # Deploy namespace first (only once)
            if ! deploy_namespace "$namespace" "$verbose"; then
                exit 1
            fi
            
            # Deploy user instances
            if [[ ${#users[@]} -eq 1 ]]; then
                deploy_user_vscode "${users[0]}" "$env_dir" "$namespace" "$verbose" "$dry_run"
            else
                deploy_users_parallel "${users[@]}" "$env_dir" "$namespace" "$verbose" "$dry_run" "$parallel"
            fi
            ;;
        undeploy)
            for user in "${users[@]}"; do
                undeploy_user_vscode "$user" "$namespace" "$verbose" "$dry_run"
            done
            ;;
        status)
            for user in "${users[@]}"; do
                check_user_status "$user" "$namespace"
            done
            ;;
    esac
}

# Execute main function
main "$@"