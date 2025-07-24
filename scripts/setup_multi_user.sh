#!/bin/bash

# Multi-User Workshop Setup Script
# Runs individual setup scripts for each user environment in parallel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
USER_ENV_DIR="${REPO_ROOT}/user_environments"
SETUP_SCRIPT="${SCRIPT_DIR}/exercise0/setup_workshop.sh"
MAX_PARALLEL=5
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
Multi-User Workshop Setup

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -d, --directory DIR     User environments directory (default: user_environments)
    -p, --parallel NUM      Max parallel setups (default: ${MAX_PARALLEL})
    -u, --users RANGE       User range (e.g., 1-5, 3,7,9, or single number)
    --vscode                Also deploy VSCode server instances
    --vscode-only           Deploy only VSCode (skip AAP setup)
    --generate-emails       Generate email notifications after setup
    --resume                Resume failed setups only
    --force                 Force re-setup even if already completed
    --dry-run               Show what would be done without executing
    -v, --verbose           Verbose output
    -h, --help              Show this help

DESCRIPTION:
    This script runs the workshop setup process for multiple user environments
    in parallel. Each user gets their own isolated setup with their specific
    credentials and configuration.

    The script:
    1. Identifies all user .env files in the directory
    2. Runs setup_workshop.sh for each user environment
    3. Logs progress and results for each user
    4. Provides consolidated status reporting

EXAMPLES:
    $0                                  # Setup all users with default settings
    $0 -u 1-10                         # Setup users 1 through 10
    $0 -u 5,7,12                       # Setup specific users
    $0 -p 10                           # Run 10 setups in parallel
    $0 --resume                        # Resume only failed setups
    $0 --dry-run                       # Preview what would be done

OUTPUT:
    user_environments/logs/
    ├── setup_user01.log              # Individual user logs
    ├── setup_user02.log
    ├── ...
    ├── multi_setup_summary.txt       # Overall summary
    └── multi_setup_progress.log      # Real-time progress

EOF
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    if [[ ! -d "${USER_ENV_DIR}" ]]; then
        error "User environments directory not found: ${USER_ENV_DIR}"
        error "Run './scripts/parse_workshop_details.sh' first to create user environments"
        exit 1
    fi
    
    if [[ ! -x "${SETUP_SCRIPT}" ]]; then
        error "Setup script not found or not executable: ${SETUP_SCRIPT}"
        exit 1
    fi
    
    # Check for .env files
    local env_files
    env_files=$(find "${USER_ENV_DIR}" -name ".env[0-9][0-9]" -type f | wc -l)
    if [[ "${env_files}" -eq 0 ]]; then
        error "No user environment files found in ${USER_ENV_DIR}"
        error "Expected files like .env01, .env02, etc."
        exit 1
    fi
    
    success "Found ${env_files} user environment(s)"
}

create_log_directory() {
    log "Creating log directory: ${LOG_DIR}"
    mkdir -p "${LOG_DIR}"
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

get_user_list() {
    local user_range="$1"
    local resume_mode="$2"
    local users=()
    
    if [[ -n "${user_range}" ]]; then
        # Use specified range
        local user_list
        user_list=$(parse_user_range "${user_range}")
        users=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && users+=("$line")
        done <<< "$user_list"
    else
        # Auto-detect all users
        local user_list
        user_list=$(find "${USER_ENV_DIR}" -name ".env[0-9][0-9]" -type f | \
                   sed 's/.*\.env\([0-9][0-9]\)/\1/' | sort)
        users=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && users+=("$line")
        done <<< "$user_list"
    fi
    
    # Filter for resume mode
    if [[ "${resume_mode}" == "true" ]]; then
        local filtered_users=()
        for user in "${users[@]}"; do
            local status_file="${LOG_DIR}/setup_user${user}.status"
            if [[ -f "${status_file}" ]]; then
                local status
                status=$(cat "${status_file}")
                if [[ "${status}" != "completed" ]]; then
                    filtered_users+=("${user}")
                fi
            else
                filtered_users+=("${user}")
            fi
        done
        # Handle empty array case for bash set -u compatibility
        if [[ ${#filtered_users[@]} -gt 0 ]]; then
            users=("${filtered_users[@]}")
        else
            users=()
        fi
    fi
    
    # Handle empty array case for bash set -u compatibility
    if [[ ${#users[@]} -gt 0 ]]; then
        printf '%s\n' "${users[@]}"
    fi
}

setup_user_environment() {
    local user_num="$1"
    local force_mode="$2"
    local verbose="$3"
    
    local env_file="${USER_ENV_DIR}/.env${user_num}"
    local log_file="${LOG_DIR}/setup_user${user_num}.log"
    local status_file="${LOG_DIR}/setup_user${user_num}.status"
    local progress_log="${LOG_DIR}/multi_setup_progress.log"
    
    # Check if already completed and not forcing
    if [[ "${force_mode}" == "false" && -f "${status_file}" ]]; then
        local status
        status=$(cat "${status_file}")
        if [[ "${status}" == "completed" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] User ${user_num}: Already completed, skipping" >> "${progress_log}"
            return 0
        fi
    fi
    
    # Check if environment file exists
    if [[ ! -f "${env_file}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] User ${user_num}: Environment file not found: ${env_file}" >> "${progress_log}"
        echo "failed" > "${status_file}"
        return 1
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] User ${user_num}: Starting setup" >> "${progress_log}"
    echo "running" > "${status_file}"
    
    # Source the user's environment and run setup
    (
        # Create a temporary details.txt for this user
        local temp_details_dir="${USER_ENV_DIR}/temp_user${user_num}"
        mkdir -p "${temp_details_dir}"
        
        # Convert .env back to details.txt format for the setup script
        create_user_details_file "${env_file}" "${temp_details_dir}/details.txt"
        
        # Run setup in the temporary directory
        cd "${temp_details_dir}"
        
        # Set environment variables
        export USER_NUMBER="${user_num}"
        export ENV_FILE="${env_file}"
        export USE_PUBLISHED_EE=true
        export SKIP_INTERACTIVE=true
        
        # Run the setup script
        "${SETUP_SCRIPT}" 2>&1
        
        # Clean up temporary directory
        rm -rf "${temp_details_dir}"
        
    ) > "${log_file}" 2>&1
    
    local setup_exit_code=$?
    
    if [[ ${setup_exit_code} -eq 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] User ${user_num}: Setup completed successfully" >> "${progress_log}"
        echo "completed" > "${status_file}"
        return 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] User ${user_num}: Setup failed (exit code: ${setup_exit_code})" >> "${progress_log}"
        echo "failed" > "${status_file}"
        return 1
    fi
}

create_user_details_file() {
    local env_file="$1"
    local details_file="$2"
    
    # Source the env file to get variables
    source "${env_file}"
    
    # Create a details.txt in the expected format
    cat << EOF > "${details_file}"
aap_controller_web_url
${AAP_URL}

aap_controller_admin_user
${AAP_USERNAME}

aap_controller_admin_password
${AAP_PASSWORD}

aap_controller_token
${AAP_TOKEN:-}

bastion_public_hostname
${SSH_HOST}

bastion_ssh_port
${SSH_PORT}

bastion_ssh_user_name
${SSH_USER}

bastion_ssh_password
${SSH_PASSWORD}

openshift_console_url
${OCP_CONSOLE_URL}

openshift_api_url
${OCP_API_URL}

openshift_bearer_token
${OCP_BEARER_TOKEN:-}

openshift_client_download_url
${OCP_CLIENT_DOWNLOAD_URL}

openshift_cluster_ingress_domain
${OCP_CLUSTER_DOMAIN}

guid
${WORKSHOP_GUID}

openshift_kubeadmin_password
${OCP_KUBEADMIN_PASSWORD:-}
EOF
}

run_parallel_setups() {
    local users=("$@")
    local max_parallel="$1"
    local force_mode="$2"
    local verbose="$3"
    local dry_run="$4"
    
    # Remove the first 4 arguments (options), leaving only user numbers
    shift 4
    users=("$@")
    
    local total_users=${#users[@]}
    local completed=0
    local failed=0
    local running=0
    local pids=()
    
    log "Starting setup for ${total_users} users (max ${max_parallel} parallel)"
    
    # Initialize progress log
    local progress_log="${LOG_DIR}/multi_setup_progress.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Multi-user setup started for ${total_users} users" > "${progress_log}"
    
    for user in "${users[@]}"; do
        # Wait if we've reached the parallel limit
        while [[ ${running} -ge ${max_parallel} ]]; do
            # Check for completed processes
            local new_pids=()
            if [[ ${#pids[@]} -gt 0 ]]; then
                for pid in "${pids[@]}"; do
                if kill -0 "${pid}" 2>/dev/null; then
                    new_pids+=("${pid}")
                else
                    wait "${pid}"
                    local exit_code=$?
                    if [[ ${exit_code} -eq 0 ]]; then
                        ((completed++))
                    else
                        ((failed++))
                    fi
                    ((running--))
                fi
                done
            fi
            # Handle empty array case for bash set -u compatibility
            if [[ ${#new_pids[@]} -gt 0 ]]; then
                pids=("${new_pids[@]}")
            else
                pids=()
            fi
            
            if [[ ${running} -ge ${max_parallel} ]]; then
                sleep 2
            fi
        done
        
        # Start setup for this user
        if [[ "${dry_run}" == "true" ]]; then
            log "Would setup user ${user}"
        else
            log "Starting setup for user ${user} (${completed}/${total_users} completed, ${failed} failed)"
            setup_user_environment "${user}" "${force_mode}" "${verbose}" &
            pids+=($!)
            ((running++))
        fi
    done
    
    # Wait for all remaining processes
    if [[ "${dry_run}" == "false" && ${#pids[@]} -gt 0 ]]; then
        for pid in "${pids[@]}"; do
            wait "${pid}"
            local exit_code=$?
            if [[ ${exit_code} -eq 0 ]]; then
                ((completed++))
            else
                ((failed++))
            fi
        done
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Multi-user setup completed: ${completed} succeeded, ${failed} failed" >> "${progress_log}"
    
    return $(( failed > 0 ? 1 : 0 ))
}

generate_summary() {
    local users=("$@")
    local summary_file="${LOG_DIR}/multi_setup_summary.txt"
    
    log "Generating setup summary..."
    
    local total_users=${#users[@]}
    local completed=0
    local failed=0
    local running=0
    
    # Count status
    for user in "${users[@]}"; do
        local status_file="${LOG_DIR}/setup_user${user}.status"
        if [[ -f "${status_file}" ]]; then
            local status
            status=$(cat "${status_file}")
            case "${status}" in
                completed) ((completed++)) ;;
                failed) ((failed++)) ;;
                running) ((running++)) ;;
            esac
        fi
    done
    
    # Generate summary
    cat << EOF > "${summary_file}"
Multi-User Workshop Setup Summary
Generated on: $(date)

Total Users: ${total_users}
Completed: ${completed}
Failed: ${failed}
Running: ${running}

User Details:
EOF
    
    # Add individual user status
    for user in "${users[@]}"; do
        local status_file="${LOG_DIR}/setup_user${user}.status"
        local env_file="${USER_ENV_DIR}/.env${user}"
        local email=""
        
        if [[ -f "${env_file}" ]]; then
            email=$(grep "USER_EMAIL=" "${env_file}" | cut -d'=' -f2)
        fi
        
        local status="unknown"
        if [[ -f "${status_file}" ]]; then
            status=$(cat "${status_file}")
        fi
        
        printf "  User %s: %-10s %s\n" "${user}" "${status}" "${email}" >> "${summary_file}"
    done
    
    cat << EOF >> "${summary_file}"

Log Files:
$(for user in "${users[@]}"; do echo "  setup_user${user}.log"; done)

Progress Log: multi_setup_progress.log

Failed Setups (if any):
$(for user in "${users[@]}"; do
    status_file="${LOG_DIR}/setup_user${user}.status"
    if [[ -f "${status_file}" && "$(cat "${status_file}")" == "failed" ]]; then
        echo "  User ${user}: See setup_user${user}.log for details"
    fi
done)

Next Steps:
1. Review individual user logs for any issues
2. Run validation: ./scripts/validate_multi_user.sh
3. Resume failed setups: ./scripts/setup_multi_user.sh --resume
EOF
    
    success "Summary written to: ${summary_file}"
    
    # Display brief summary
    echo
    echo "================================="
    echo "  MULTI-USER SETUP SUMMARY"
    echo "================================="
    echo "Total Users: ${total_users}"
    echo "Completed:   ${completed}"
    echo "Failed:      ${failed}"
    echo "Running:     ${running}"
    echo
    
    if [[ ${failed} -gt 0 ]]; then
        warning "Some setups failed. Check individual logs and run with --resume to retry."
        return 1
    else
        success "All user setups completed successfully!"
        return 0
    fi
}

main() {
    local user_env_dir="${USER_ENV_DIR}"
    local max_parallel="${MAX_PARALLEL}"
    local user_range=""
    local resume_mode="false"
    local force_mode="false"
    local dry_run="false"
    local verbose="false"
    local deploy_vscode="false"
    local vscode_only="false"
    local generate_emails="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--directory)
                user_env_dir="$2"
                shift 2
                ;;
            -p|--parallel)
                max_parallel="$2"
                shift 2
                ;;
            -u|--users)
                user_range="$2"
                shift 2
                ;;
            --vscode)
                deploy_vscode="true"
                shift
                ;;
            --vscode-only)
                vscode_only="true"
                deploy_vscode="true"
                shift
                ;;
            --generate-emails)
                generate_emails="true"
                shift
                ;;
            --resume)
                resume_mode="true"
                shift
                ;;
            --force)
                force_mode="true"
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
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Update global variables
    USER_ENV_DIR="${user_env_dir}"
    LOG_DIR="${USER_ENV_DIR}/logs"
    
    # Run the setup process
    check_prerequisites
    create_log_directory
    
    # Get list of users to process
    local users=()
    local user_list
    user_list=$(get_user_list "${user_range}" "${resume_mode}")
    while IFS= read -r line; do
        [[ -n "$line" ]] && users+=("$line")
    done <<< "$user_list"
    
    if [[ ${#users[@]} -eq 0 ]]; then
        if [[ "${resume_mode}" == "true" ]]; then
            success "No failed setups to resume. All users completed successfully!"
            exit 0
        else
            error "No users found to process"
            exit 1
        fi
    fi
    
    log "Processing users: ${users[*]}"
    
    # Run AAP setups unless vscode-only mode
    local aap_success=true
    if [[ "${vscode_only}" == "false" ]]; then
        if ! run_parallel_setups "${max_parallel}" "${force_mode}" "${verbose}" "${dry_run}" "${users[@]}"; then
            aap_success=false
        fi
    fi
    
    # Deploy VSCode if requested
    local vscode_success=true
    if [[ "${deploy_vscode}" == "true" ]]; then
        log "Deploying VSCode server instances..."
        local vscode_script="${SCRIPT_DIR}/deploy_vscode.sh"
        
        if [[ ! -f "${vscode_script}" ]]; then
            error "VSCode deployment script not found: ${vscode_script}"
            vscode_success=false
        else
            local vscode_args=("-d" "${user_env_dir}" "-p" "${max_parallel}")
            
            if [[ -n "${user_range}" ]]; then
                vscode_args+=("-u" "${user_range}")
            fi
            
            if [[ "${verbose}" == "true" ]]; then
                vscode_args+=("-v")
            fi
            
            if [[ "${dry_run}" == "true" ]]; then
                vscode_args+=("--dry-run")
            fi
            
            if ! "${vscode_script}" "${vscode_args[@]}"; then
                error "VSCode deployment failed"
                vscode_success=false
            else
                success "VSCode server instances deployed successfully"
            fi
        fi
    fi
    
    # Generate emails if requested
    if [[ "${generate_emails}" == "true" && "${dry_run}" == "false" ]]; then
        if [[ "${aap_success}" == "true" && "${vscode_success}" == "true" ]]; then
            log "Generating email notifications..."
            local email_script="${SCRIPT_DIR}/generate_workshop_emails.sh"
            
            if [[ ! -f "${email_script}" ]]; then
                error "Email generation script not found: ${email_script}"
            else
                local email_args=("-d" "${user_env_dir}")
                
                if [[ -n "${user_range}" ]]; then
                    email_args+=("-u" "${user_range}")
                fi
                
                if [[ "${verbose}" == "true" ]]; then
                    email_args+=("-v")
                fi
                
                if "${email_script}" "${email_args[@]}"; then
                    success "Email notifications generated successfully!"
                    log "Check the workshop_emails/ directory for delivery options"
                else
                    warning "Email generation failed, but setup was successful"
                fi
            fi
        else
            warning "Skipping email generation due to setup failures"
        fi
    fi
    
    # Generate summary and determine exit status
    if [[ "${dry_run}" == "false" ]]; then
        generate_summary "${users[@]}"
    fi
    
    if [[ "${aap_success}" == "true" && "${vscode_success}" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"