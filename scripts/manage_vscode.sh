#!/bin/bash

# VSCode Server Management Script for AAP Workshop
# Simple wrapper for common VSCode management tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VSCODE_SCRIPT="${SCRIPT_DIR}/deploy_vscode.sh"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

usage() {
    cat << EOF
VSCode Server Management for AAP Workshop

USAGE:
    $0 <action> [options]

ACTIONS:
    deploy          Deploy VSCode instances for all users
    undeploy        Remove VSCode instances for all users
    status          Check VSCode deployment status
    restart         Restart VSCode instances
    logs            Show VSCode pod logs
    url             Get VSCode URLs for users

OPTIONS:
    -u, --users RANGE    User range (e.g., 1-5, specific users)
    -v, --verbose        Verbose output
    -h, --help           Show this help

EXAMPLES:
    $0 deploy                    # Deploy VSCode for all users
    $0 deploy -u 1-10           # Deploy for users 1-10
    $0 status                   # Check all deployments
    $0 url -u 5                 # Get URL for user 5
    $0 logs -u 3                # Show logs for user 3
    $0 undeploy                 # Remove all VSCode instances

EOF
}

check_prerequisites() {
    if [[ ! -f "$VSCODE_SCRIPT" ]]; then
        log_error "VSCode deployment script not found: $VSCODE_SCRIPT"
        return 1
    fi
    
    if ! command -v oc &> /dev/null; then
        log_error "OpenShift CLI 'oc' not found"
        return 1
    fi
    
    if ! oc whoami &> /dev/null; then
        log_error "Not logged into OpenShift"
        return 1
    fi
}

get_user_urls() {
    local user_range="$1"
    local namespace="workshop-vscode"
    
    if [[ -n "$user_range" ]]; then
        # Parse user range and show specific users
        local users
        if [[ $user_range =~ ^[0-9]+$ ]]; then
            users=("$user_range")
        elif [[ $user_range =~ ^[0-9]+-[0-9]+$ ]]; then
            local start=$(echo "$user_range" | cut -d'-' -f1)
            local end=$(echo "$user_range" | cut -d'-' -f2)
            users=()
            for ((i=start; i<=end; i++)); do
                users+=("$i")
            done
        else
            log_error "Invalid user range: $user_range"
            return 1
        fi
        
        for user in "${users[@]}"; do
            local user_padded
            user_padded=$(printf "%02d" "$user")
            local route_url
            if route_url=$(oc get route "vscode-user${user_padded}" -n "$namespace" -o jsonpath='{.spec.host}' 2>/dev/null); then
                echo "User $user_padded: https://$route_url"
            else
                echo "User $user_padded: NOT DEPLOYED"
            fi
        done
    else
        # Show all VSCode routes
        log_info "All VSCode URLs:"
        oc get routes -n "$namespace" -o custom-columns=NAME:.metadata.name,URL:.spec.host --no-headers | \
            grep "vscode-user" | \
            while read -r name host; do
                local user_num=${name#vscode-user}
                echo "User $user_num: https://$host"
            done
    fi
}

show_user_logs() {
    local user_range="$1"
    local namespace="workshop-vscode"
    
    if [[ -z "$user_range" ]]; then
        log_error "User range required for logs command"
        return 1
    fi
    
    local user_padded
    user_padded=$(printf "%02d" "$user_range")
    
    local pod_name
    if pod_name=$(oc get pods -n "$namespace" -l app="vscode-user${user_padded}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); then
        log_info "Showing logs for VSCode user $user_padded (pod: $pod_name)"
        oc logs -n "$namespace" "$pod_name" -f
    else
        log_error "No VSCode pod found for user $user_padded"
        return 1
    fi
}

restart_vscode() {
    local user_range="$1"
    local namespace="workshop-vscode"
    
    if [[ -n "$user_range" ]]; then
        # Restart specific users
        local users
        if [[ $user_range =~ ^[0-9]+$ ]]; then
            users=("$user_range")
        elif [[ $user_range =~ ^[0-9]+-[0-9]+$ ]]; then
            local start=$(echo "$user_range" | cut -d'-' -f1)
            local end=$(echo "$user_range" | cut -d'-' -f2)
            users=()
            for ((i=start; i<=end; i++)); do
                users+=("$i")
            done
        else
            log_error "Invalid user range: $user_range"
            return 1
        fi
        
        for user in "${users[@]}"; do
            local user_padded
            user_padded=$(printf "%02d" "$user")
            log_info "Restarting VSCode for user $user_padded..."
            oc rollout restart deployment/vscode-user${user_padded} -n "$namespace"
        done
    else
        # Restart all VSCode deployments
        log_info "Restarting all VSCode deployments..."
        oc get deployments -n "$namespace" -o name | \
            grep "vscode-user" | \
            xargs -I {} oc rollout restart {} -n "$namespace"
    fi
}

main() {
    local action=""
    local user_range=""
    local verbose="false"
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    action="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--users)
                user_range="$2"
                shift 2
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
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Execute action
    case "$action" in
        deploy)
            local args=()
            if [[ -n "$user_range" ]]; then
                args+=("-u" "$user_range")
            fi
            if [[ "$verbose" == "true" ]]; then
                args+=("-v")
            fi
            "$VSCODE_SCRIPT" --deploy "${args[@]}"
            ;;
        undeploy)
            local args=()
            if [[ -n "$user_range" ]]; then
                args+=("-u" "$user_range")
            fi
            if [[ "$verbose" == "true" ]]; then
                args+=("-v")
            fi
            "$VSCODE_SCRIPT" --undeploy "${args[@]}"
            ;;
        status)
            local args=()
            if [[ -n "$user_range" ]]; then
                args+=("-u" "$user_range")
            fi
            "$VSCODE_SCRIPT" --status "${args[@]}"
            ;;
        url|urls)
            get_user_urls "$user_range"
            ;;
        logs)
            show_user_logs "$user_range"
            ;;
        restart)
            restart_vscode "$user_range"
            ;;
        *)
            log_error "Unknown action: $action"
            usage
            exit 1
            ;;
    esac
}

main "$@"