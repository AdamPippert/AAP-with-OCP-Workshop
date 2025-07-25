#!/bin/bash

# VSCode Server Deployment Script for AAP Workshop
# Deploys VSCode server instances for workshop users

set -euo pipefail

# Default configuration
DEFAULT_NAMESPACE="workshop-vscode"
DEFAULT_ENV_DIR="user_environments"
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
    -n, --namespace NAME    VSCode namespace (default: workshop-vscode)
    --deploy                Deploy VSCode instances (default action)
    --undeploy              Remove VSCode instances
    --status                Check deployment status
    --dry-run               Preview without executing
    -v, --verbose           Detailed output
    -h, --help              Show this help

MULTI-CLUSTER DEPLOYMENT:
    This script automatically logs into each user's individual OpenShift cluster
    based on credentials in their .env files. Bearer tokens are automatically
    updated from workshop_details*.txt files before deployment.

EXAMPLES:
    $0                          # Deploy VSCode for all users (multi-cluster)
    $0 -u 1-10                  # Deploy for users 1-10 across their clusters
    $0 --undeploy -u 5          # Remove VSCode for user 5 from their cluster
    $0 --status                 # Check all deployments across clusters
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

# Check if OpenShift CLI is available
check_oc_command() {
    if ! command -v oc &> /dev/null; then
        log_error "OpenShift CLI 'oc' not found. Please install it."
        return 1
    fi
}

# Login to a specific user's cluster
login_to_user_cluster() {
    local user_num="$1"
    local env_dir="$2"
    local user_env_file="${env_dir}/.env$(printf "%02d" "$user_num")"
    
    if [[ ! -f "$user_env_file" ]]; then
        log_error "User environment file not found: $user_env_file"
        return 1
    fi
    
    # Source the user environment to get cluster credentials
    set -a  # automatically export all variables
    # shellcheck disable=SC1090
    source "$user_env_file"
    set +a
    
    if [[ -z "$OCP_API_URL" ]]; then
        log_error "OCP_API_URL not found in $user_env_file"
        return 1
    fi
    
    log_info "Logging into cluster for User $(printf "%02d" "$user_num"): $OCP_API_URL"
    
    # Try to use bearer token if available
    if [[ -n "$OCP_BEARER_TOKEN" ]]; then
        if oc login --token="$OCP_BEARER_TOKEN" --server="$OCP_API_URL" --insecure-skip-tls-verify=true &>/dev/null; then
            log_info "Logged in using bearer token"
            return 0
        fi
    fi
    
    # If no bearer token, try with kubeadmin password if available
    if [[ -n "$OCP_KUBEADMIN_PASSWORD" ]]; then
        if oc login -u kubeadmin -p "$OCP_KUBEADMIN_PASSWORD" --server="$OCP_API_URL" --insecure-skip-tls-verify=true &>/dev/null; then
            log_info "Logged in using kubeadmin credentials"
            return 0
        fi
    fi
    
    # Fallback: prompt for credentials
    log_warn "No bearer token or kubeadmin password available for User $(printf "%02d" "$user_num")"
    log_warn "Attempting login with server only (may prompt for credentials)"
    
    if oc login --server="$OCP_API_URL" --insecure-skip-tls-verify=true; then
        log_info "Logged in to User $(printf "%02d" "$user_num") cluster"
        return 0
    else
        log_error "Failed to login to User $(printf "%02d" "$user_num") cluster"
        return 1
    fi
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

# Deploy VSCode instance for a single user in their specific cluster
deploy_user_vscode() {
    local user_num="$1"
    local env_dir="$2"
    local namespace="$3"
    local verbose="$4"
    local dry_run="$5"
    
    local user_num_padded
    user_num_padded=$(printf "%02d" "$user_num")
    
    log_info "=== Deploying VSCode for User $user_num_padded ==="
    
    # Login to user's specific cluster first
    if ! login_to_user_cluster "$user_num" "$env_dir"; then
        log_error "Failed to login to User $user_num_padded cluster"
        return 1
    fi
    
    # Load user environment
    if ! load_user_env "$user_num" "$env_dir"; then
        return 1
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN: Would deploy VSCode for user $user_num_padded in their individual cluster"
        log_info "Cluster: $OCP_API_URL"
        log_info "User Email: $USER_EMAIL"
        return 0
    fi
    
    # Create namespace and basic resources in this user's cluster
    log_info "Creating namespace and resources in user's cluster..."
    
    # Create namespace
    oc create namespace "$namespace" --dry-run=client -o yaml | oc apply -f -
    
    # Create service account with required permissions
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vscode-workshop
  namespace: $namespace
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vscode-workshop-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: vscode-workshop
  namespace: $namespace
EOF
    
    # Generate VSCode URL and password if not present
    if [[ -z "${VSCODE_URL:-}" ]]; then
        if [[ -n "$OCP_CLUSTER_DOMAIN" ]]; then
            VSCODE_URL="https://vscode-user${user_num_padded}.${OCP_CLUSTER_DOMAIN}"
        else
            log_error "Cannot determine VSCode URL for user $user_num_padded - missing OCP_CLUSTER_DOMAIN"
            return 1
        fi
        
        # Add VSCode URL to the .env file for future use
        echo "VSCODE_URL=${VSCODE_URL}" >> "${env_dir}/.env${user_num_padded}"
        
        # Generate VSCode password if not present
        if [[ -z "${VSCODE_PASSWORD:-}" ]]; then
            VSCODE_PASSWORD="workshop-user${user_num_padded}"
            echo "VSCODE_PASSWORD=${VSCODE_PASSWORD}" >> "${env_dir}/.env${user_num_padded}"
        fi
        
        log_info "Generated VSCode URL: $VSCODE_URL"
    fi
    
    # Get available storage class
    local storage_classes=($(oc get sc -o name 2>/dev/null | sed 's/storageclass.storage.k8s.io\///' || echo ""))
    local preferred=("gp3-csi" "gp2" "standard" "default")
    local storage_class="standard"  # fallback
    
    for pref in "${preferred[@]}"; do
        for sc in "${storage_classes[@]}"; do
            if [[ "$sc" == "$pref" ]]; then
                storage_class="$sc"
                break 2
            fi
        done
    done
    
    if [[ ${#storage_classes[@]} -gt 0 && "$storage_class" == "standard" ]]; then
        storage_class="${storage_classes[0]}"
    fi
    
    local cluster_domain=$(echo "$VSCODE_URL" | sed 's|https://vscode-user[0-9]*\.||')
    local user_id="user${user_num_padded}"
    
    log_info "Using storage class: $storage_class"
    
    # Deploy VSCode resources for this user
    # (This would use the same YAML from the emergency script but templated)
    # For now, use the original template approach but ensure we have the namespace
    local template_params=(
        "USER_NUMBER=$user_num_padded"
        "USER_EMAIL=$USER_EMAIL"
        "WORKSHOP_GUID=$WORKSHOP_GUID"
        "OCP_CLUSTER_DOMAIN=$OCP_CLUSTER_DOMAIN"
        "AAP_URL=$AAP_URL"
        "VSCODE_URL=${VSCODE_URL}"
        "VSCODE_PASSWORD=${VSCODE_PASSWORD:-workshop-user${user_num_padded}}"
        "STORAGE_CLASS=$storage_class"
    )
    
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
    
    log_success "VSCode deployed for user $user_num_padded - ${VSCODE_URL}"
    
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

# Sequential deployment function for multi-cluster (can't parallelize across different clusters)
deploy_users_sequential() {
    local users=("$@")
    local env_dir="$2"
    local namespace="$3"
    local verbose="$4"
    local dry_run="$5"
    
    # Remove function parameters from users array  
    users=("${users[@]:5}")
    
    local success=0
    local failed=0
    local failed_users=()
    local total_users=${#users[@]}
    
    log_info "Deploying VSCode for $total_users users across their individual clusters..."
    log_warn "Multi-cluster deployment requires sequential processing (cannot parallelize)"
    
    for user in "${users[@]}"; do
        log_info "Processing User $(printf "%02d" "$user") (${success}/${total_users} completed)"
        
        if deploy_user_vscode "$user" "$env_dir" "$namespace" "$verbose" "$dry_run"; then
            ((success++))
        else
            ((failed++))
            failed_users+=("$user")
        fi
        
        # Brief pause between deployments to avoid overwhelming clusters
        sleep 2
    done
    
    log_info "Multi-cluster deployment complete: $success/$total_users successful"
    
    if [[ ${#failed_users[@]} -gt 0 ]]; then
        log_warn "Failed users: ${failed_users[*]}"
        log_info "You can retry failed users individually with:"
        for failed_user in "${failed_users[@]}"; do
            echo "  $0 --users $failed_user"
        done
    fi
    
    return $failed
}

# Update bearer tokens from workshop_details files  
update_bearer_tokens() {
    local env_dir="$1"
    local verbose="$2"
    
    local update_script="${SCRIPT_DIR}/update_bearer_tokens.sh"
    
    if [[ -f "$update_script" ]]; then
        log_info "Updating bearer tokens from workshop_details files..."
        local update_args=("-d" "$env_dir")
        
        if [[ "$verbose" == "true" ]]; then
            update_args+=("--verbose")
        fi
        
        if "$update_script" "${update_args[@]}"; then
            log_info "Bearer tokens updated successfully"
        else
            log_warn "Bearer token update failed, will attempt login with available credentials"
        fi
    else
        log_warn "Bearer token update script not found: $update_script"
        log_warn "Proceeding with existing credentials in .env files"
    fi
}

# Main function
main() {
    local env_dir="$DEFAULT_ENV_DIR"
    local namespace="$DEFAULT_NAMESPACE"
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
    
    # Check OpenShift CLI
    if ! check_oc_command; then
        exit 1
    fi
    
    # Update bearer tokens from workshop details files
    if [[ "$action" == "deploy" ]]; then
        update_bearer_tokens "$env_dir" "$verbose"
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
            # Multi-cluster deployment - each user gets their own cluster
            log_warn "Multi-cluster deployment: Connecting to each user's individual OpenShift cluster"
            
            if [[ ${#users[@]} -eq 1 ]]; then
                deploy_user_vscode "${users[0]}" "$env_dir" "$namespace" "$verbose" "$dry_run"
            else
                deploy_users_sequential "${users[@]}" "$env_dir" "$namespace" "$verbose" "$dry_run"
            fi
            ;;
        undeploy)
            log_warn "Multi-cluster undeploy: Will connect to each user's individual cluster"
            for user in "${users[@]}"; do
                # Login to user's specific cluster first
                if login_to_user_cluster "$user" "$env_dir"; then
                    undeploy_user_vscode "$user" "$namespace" "$verbose" "$dry_run"
                else
                    log_error "Failed to login to User $(printf "%02d" "$user") cluster - skipping undeploy"
                fi
            done
            ;;
        status)
            log_warn "Multi-cluster status: Will connect to each user's individual cluster"
            for user in "${users[@]}"; do
                # Login to user's specific cluster first
                if login_to_user_cluster "$user" "$env_dir"; then
                    check_user_status "$user" "$namespace"
                else
                    echo "User $(printf "%02d" "$user"): LOGIN FAILED"
                fi
            done
            ;;
    esac
}

# Execute main function
main "$@"