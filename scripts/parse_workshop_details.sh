#!/bin/bash

# Workshop Details Parser
# Parses bulk workshop_details.txt and creates individual .env files for each user

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSHOP_DETAILS_FILE="${REPO_ROOT}/workshop_details.txt"
OUTPUT_DIR="${REPO_ROOT}/user_environments"
AUTO_DISCOVER=true

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
Workshop Details Parser

USAGE:
    $0 [OPTIONS] [FILES...]

OPTIONS:
    -f, --file FILE         Workshop details file (default: auto-discover)
    -o, --output DIR        Output directory for user environments (default: user_environments)
    --files FILE1,FILE2     Comma-separated list of workshop details files
    --auto-discover         Auto-discover workshop_details*.txt files (default)
    --no-auto-discover      Disable auto-discovery, use only specified files
    --dry-run               Show what would be parsed without creating files
    -v, --verbose           Verbose output
    -h, --help              Show this help

DESCRIPTION:
    This script parses workshop details files and creates individual .env files
    for each user environment. It supports multiple files for large workshops
    that exceed the user limit per RHDP environment.
    
    Each user gets:
    - Individual .envXX file (where XX is user number)
    - Continuous numbering across multiple files
    - User assignment tracking in users.csv
    - Environment-specific configuration
    
EXAMPLES:
    $0                                          # Auto-discover and parse all files
    $0 -f workshop_details.txt                 # Parse single specific file
    $0 --files workshop_details.txt,workshop_details2.txt  # Parse specific files
    $0 --no-auto-discover -f custom.txt       # Parse only specified file
    $0 --dry-run -v                           # Preview with verbose output

AUTO-DISCOVERY:
    By default, the script automatically discovers files matching the pattern:
    - workshop_details.txt
    - workshop_details2.txt
    - workshop_details3.txt
    - etc.
    
    Files are processed in numerical order to ensure consistent user numbering.

OUTPUT:
    user_environments/
    ├── .env01                 # User 1 environment (from first file)
    ├── .env02                 # User 2 environment
    ├── ...
    ├── .env31                 # User 31 environment (from second file)
    ├── .env32                 # User 32 environment
    ├── ...
    ├── users.csv              # User assignment tracking with file sources
    └── summary.txt            # Parse summary with file breakdown

EOF
}

discover_workshop_files() {
    local files=()
    
    # Look for workshop_details.txt (base file)
    if [[ -f "${REPO_ROOT}/workshop_details.txt" ]]; then
        files+=("${REPO_ROOT}/workshop_details.txt")
    fi
    
    # Look for numbered files: workshop_details2.txt, workshop_details3.txt, etc.
    for i in {2..20}; do
        local file="${REPO_ROOT}/workshop_details${i}.txt"
        if [[ -f "${file}" ]]; then
            files+=("${file}")
        fi
    done
    
    printf '%s\n' "${files[@]}"
}

check_prerequisites() {
    local files=("$@")
    
    log "Checking prerequisites for ${#files[@]} file(s)..."
    
    if [[ ${#files[@]} -eq 0 ]]; then
        error "No workshop details files found"
        if [[ "${AUTO_DISCOVER}" == "true" ]]; then
            error "Expected files like: workshop_details.txt, workshop_details2.txt, etc."
        fi
        exit 1
    fi
    
    local total_size=0
    for file in "${files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            error "Workshop details file not found: ${file}"
            exit 1
        fi
        
        if [[ ! -r "${file}" ]]; then
            error "Cannot read workshop details file: ${file}"
            exit 1
        fi
        
        if [[ ! -s "${file}" ]]; then
            error "Workshop details file is empty: ${file}"
            exit 1
        fi
        
        local file_size
        file_size=$(wc -c < "${file}")
        total_size=$((total_size + file_size))
        
        log "Found: $(basename "${file}") ($(numfmt --to=iec "${file_size}"))"
    done
    
    success "Prerequisites check passed - Total data: $(numfmt --to=iec "${total_size}")"
}

create_output_directory() {
    log "Creating output directory: ${OUTPUT_DIR}"
    
    if [[ -d "${OUTPUT_DIR}" ]]; then
        warning "Output directory already exists, contents may be overwritten"
    else
        mkdir -p "${OUTPUT_DIR}"
        success "Created output directory: ${OUTPUT_DIR}"
    fi
}

extract_field_value() {
    local content="$1"
    local pattern="$2"
    
    echo "${content}" | grep -o "${pattern}" | head -1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

extract_credentials() {
    local content="$1"
    local aws_access_key=""
    local aws_secret_key=""
    local route53_domain=""
    local console_url=""
    local console_user=""
    local console_pass=""
    local ssh_host=""
    local ssh_port=""
    local ssh_user=""
    local ssh_pass=""
    local ocp_console=""
    local ocp_api=""
    local aap_url=""
    local aap_user=""
    local aap_pass=""
    local cluster_domain=""
    local guid=""
    
    # Extract AWS credentials
    aws_access_key=$(echo "${content}" | grep "AWS_ACCESS_KEY_ID:" | head -1 | sed 's/.*AWS_ACCESS_KEY_ID:[[:space:]]*\([^[:space:]]*\).*/\1/' | tr -d '`')
    aws_secret_key=$(echo "${content}" | grep "AWS_SECRET_ACCESS_KEY:" | head -1 | sed 's/.*AWS_SECRET_ACCESS_KEY:[[:space:]]*\([^[:space:]]*\).*/\1/' | tr -d '`')
    
    # Extract Route53 domain
    route53_domain=$(echo "${content}" | grep "Top level route53 domain:" | head -1 | sed 's/.*Top level route53 domain:[[:space:]]*\([^[:space:]]*\).*/\1/')
    
    # Extract console credentials
    console_url=$(echo "${content}" | grep "Web Console Access:" | head -1 | sed 's/.*Web Console Access:[[:space:]]*\([^[:space:]]*\).*/\1/')
    console_creds=$(echo "${content}" | grep "Web Console Credentials:" | head -1 | sed 's/.*Web Console Credentials:[[:space:]]*\([^[:space:]]*\).*/\1/')
    console_user=$(echo "${console_creds}" | cut -d'/' -f1)
    console_pass=$(echo "${console_creds}" | cut -d'/' -f2)
    
    # Extract SSH details
    ssh_line=$(echo "${content}" | grep "ssh lab-user@" | head -1)
    ssh_host=$(echo "${ssh_line}" | sed 's/.*ssh lab-user@\([^[:space:]]*\).*/\1/')
    ssh_port=$(echo "${ssh_line}" | sed 's/.*-p[[:space:]]*\([0-9]*\).*/\1/')
    ssh_user="lab-user"
    ssh_pass=$(echo "${content}" | grep "password.*'" | head -1 | sed "s/.*password[[:space:]]*'\([^']*\)'.*/\1/")
    
    # Extract OpenShift details
    ocp_console=$(echo "${content}" | grep "OpenShift Console:" | head -1 | sed 's/.*OpenShift Console:[[:space:]]*\([^[:space:]]*\).*/\1/')
    ocp_api=$(echo "${content}" | grep "OpenShift API for command line" | head -1 | sed 's/.*client:[[:space:]]*\([^[:space:]]*\).*/\1/')
    
    # Extract cluster domain from console URL
    if [[ -n "${ocp_console}" ]]; then
        cluster_domain=$(echo "${ocp_console}" | sed 's|https://console-openshift-console\.||' | sed 's|/$||')
    fi
    
    # Extract GUID from cluster domain
    if [[ -n "${cluster_domain}" ]]; then
        guid=$(echo "${cluster_domain}" | sed 's/apps\.cluster-\([^.]*\)-.*/\1/')
    fi
    
    # Extract AAP details
    aap_url=$(echo "${content}" | grep "Automation Controller URL:" | head -1 | sed 's/.*Automation Controller URL:[[:space:]]*\([^[:space:]]*\).*/\1/')
    aap_user=$(echo "${content}" | grep "Automation Controller Admin Login:" | head -1 | sed 's/.*Login:[[:space:]]*\([^[:space:]]*\).*/\1/')
    aap_pass=$(echo "${content}" | grep "Automation Controller Admin Password:" | head -1 | sed 's/.*Password:[[:space:]]*\([^[:space:]]*\).*/\1/')
    
    # Return as associative array format
    cat << EOF
AWS_ACCESS_KEY_ID=${aws_access_key}
AWS_SECRET_ACCESS_KEY=${aws_secret_key}
ROUTE53_DOMAIN=${route53_domain}
CONSOLE_URL=${console_url}
CONSOLE_USER=${console_user}
CONSOLE_PASS=${console_pass}
SSH_HOST=${ssh_host}
SSH_PORT=${ssh_port}
SSH_USER=${ssh_user}
SSH_PASSWORD=${ssh_pass}
OCP_CONSOLE_URL=${ocp_console}
OCP_API_URL=${ocp_api}
OCP_CLUSTER_DOMAIN=${cluster_domain}
WORKSHOP_GUID=${guid}
AAP_URL=${aap_url}
AAP_USERNAME=${aap_user}
AAP_PASSWORD=${aap_pass}
EOF
}

parse_workshop_details() {
    local dry_run="$1"
    local verbose="$2"
    shift 2
    local files=("$@")
    
    log "Parsing ${#files[@]} workshop details file(s)..."
    
    local user_count=0
    local current_service=""
    local current_email=""
    local current_content=""
    local in_user_section=false
    local users_csv="${OUTPUT_DIR}/users.csv"
    local summary_file="${OUTPUT_DIR}/summary.txt"
    local file_stats=()
    
    # Create users CSV header
    if [[ "${dry_run}" == "false" ]]; then
        echo "User_Number,Email,Service_ID,GUID,Source_File,Status" > "${users_csv}"
    fi
    
    # Process each file
    for file_path in "${files[@]}"; do
        local file_name
        file_name=$(basename "${file_path}")
        local file_user_count=0
        
        log "Processing file: ${file_name}"
        
        # Read the file line by line
        while IFS= read -r line || [[ -n "${line}" ]]; do
            # Check if this is a service line (starts with enterprise.)
            if [[ "${line}" =~ ^enterprise\. ]]; then
                # Process previous user if we have one
                if [[ "${in_user_section}" == "true" && -n "${current_email}" ]]; then
                    user_count=$((user_count + 1))
                    file_user_count=$((file_user_count + 1))
                    process_user "${user_count}" "${current_email}" "${current_service}" "${current_content}" "${dry_run}" "${verbose}"
                    
                    # Add to users CSV
                    if [[ "${dry_run}" == "false" ]]; then
                        local guid=$(echo "${current_content}" | grep "cluster-" | head -1 | sed 's/.*cluster-\([^.]*\)-.*/\1/')
                        echo "${user_count},${current_email},${current_service},${guid},${file_name},parsed" >> "${users_csv}"
                    fi
                fi
                
                # Start new user section
                current_service="${line}"
                current_content=""
                current_email=""
                in_user_section=false
                
                if [[ "${verbose}" == "true" ]]; then
                    log "Found service: ${current_service}"
                fi
                
            # Check if this is an email line
            elif [[ "${line}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                current_email="${line}"
                in_user_section=true
                
                if [[ "${verbose}" == "true" ]]; then
                    log "Found email: ${current_email}"
                fi
                
            # Accumulate content for current user
            elif [[ "${in_user_section}" == "true" ]]; then
                current_content="${current_content}${line}"$'\n'
            fi
            
        done < "${file_path}"
        
        # Process the last user from this file
        if [[ "${in_user_section}" == "true" && -n "${current_email}" ]]; then
            user_count=$((user_count + 1))
            file_user_count=$((file_user_count + 1))
            process_user "${user_count}" "${current_email}" "${current_service}" "${current_content}" "${dry_run}" "${verbose}"
            
            # Add to users CSV
            if [[ "${dry_run}" == "false" ]]; then
                local guid=$(echo "${current_content}" | grep "cluster-" | head -1 | sed 's/.*cluster-\([^.]*\)-.*/\1/')
                echo "${user_count},${current_email},${current_service},${guid},${file_name},parsed" >> "${users_csv}"
            fi
        fi
        
        # Store file statistics
        file_stats+=("${file_name}: ${file_user_count} users")
        log "Completed ${file_name}: ${file_user_count} users processed"
        
        # Reset for next file
        current_service=""
        current_email=""
        current_content=""
        in_user_section=false
    done
    
    # Create summary
    if [[ "${dry_run}" == "false" ]]; then
        cat << EOF > "${summary_file}"
Workshop Details Parse Summary
Generated on: $(date)

Total Users Processed: ${user_count}
Output Directory: ${OUTPUT_DIR}
Source Files: ${#files[@]} file(s)

File Statistics:
$(printf '  %s\n' "${file_stats[@]}")

Source Files Processed:
$(printf '  %s\n' "${files[@]}")

Files Created:
$(for i in $(seq 1 ${user_count}); do printf "  .env%02d\n" $i; done)
  users.csv
  summary.txt

User Distribution:
$(if [[ ${user_count} -le 30 ]]; then
    echo "  Single environment workshop (${user_count} users)"
else
    echo "  Multi-environment workshop (${user_count} users across ${#files[@]} environments)"
    local users_per_env=$((30))
    local full_envs=$((user_count / users_per_env))
    local remaining=$((user_count % users_per_env))
    if [[ ${remaining} -gt 0 ]]; then
        echo "  ${full_envs} full environments (30 users each) + 1 partial environment (${remaining} users)"
    else
        echo "  ${full_envs} full environments (30 users each)"
    fi
fi)

Next Steps:
1. Review individual .env files for accuracy
2. Check user assignments: cat user_environments/users.csv
3. Run multi-user setup: ./scripts/setup_multi_user.sh
4. Validate all environments: ./scripts/validate_multi_user.sh
EOF
    fi
    
    success "Parsed ${user_count} user environments"
    return 0
}

process_user() {
    local user_num="$1"
    local email="$2"
    local service="$3"
    local content="$4"
    local dry_run="$5"
    local verbose="$6"
    
    local env_file
    env_file=$(printf "${OUTPUT_DIR}/.env%02d" "${user_num}")
    
    if [[ "${dry_run}" == "true" ]]; then
        log "Would create ${env_file} for ${email}"
        if [[ "${verbose}" == "true" ]]; then
            log "Service: ${service}"
            log "Content preview: $(echo "${content}" | head -3 | tr '\n' ' ')..."
        fi
        return 0
    fi
    
    if [[ "${verbose}" == "true" ]]; then
        log "Processing user ${user_num}: ${email}"
    fi
    
    # Extract credentials from content
    local credentials
    credentials=$(extract_credentials "${content}")
    
    # Create .env file
    cat << EOF > "${env_file}"
# Workshop Environment Configuration for User ${user_num}
# Generated from workshop_details.txt on $(date)
# Email: ${email}
# Service: ${service}

# User Assignment
USER_NUMBER=${user_num}
USER_EMAIL=${email}
SERVICE_ID=${service}

${credentials}

# Additional OpenShift Configuration (derived)
OCP_BEARER_TOKEN=
OCP_CLIENT_DOWNLOAD_URL=http://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.16/openshift-client-linux.tar.gz
OCP_KUBEADMIN_PASSWORD=

# SSH Bastion Access (parsed from details)
# Use the credentials provided in the parsed section above

# AAP Token (to be generated during setup)
AAP_TOKEN=

# Workshop Configuration
WORKSHOP_USER_NUM=$(printf "%02d" "${user_num}")
SKIP_INTERACTIVE=true
USE_PUBLISHED_EE=true
EOF
    
    if [[ "${verbose}" == "true" ]]; then
        success "Created ${env_file}"
    fi
}

show_summary() {
    local user_count="$1"
    local dry_run="$2"
    
    echo
    echo "=================================="
    echo "  WORKSHOP DETAILS PARSE COMPLETE"
    echo "=================================="
    echo
    echo "Users processed: ${user_count}"
    
    if [[ "${dry_run}" == "true" ]]; then
        echo "Mode: DRY RUN (no files created)"
    else
        echo "Output directory: ${OUTPUT_DIR}"
        echo "Files created:"
        echo "  - $(printf ".env%02d " $(seq 1 ${user_count}))"
        echo "  - users.csv"
        echo "  - summary.txt"
    fi
    
    echo
    echo "Next steps:"
    if [[ "${dry_run}" == "true" ]]; then
        echo "  1. Run without --dry-run to create files"
        echo "  2. Review the parsing results"
    else
        echo "  1. Review individual .env files: ls ${OUTPUT_DIR}/"
        echo "  2. Run multi-user setup: ./scripts/setup_multi_user.sh"
        echo "  3. Monitor progress: tail -f ${OUTPUT_DIR}/setup_*.log"
    fi
    echo
}

main() {
    local workshop_file=""
    local output_dir="${OUTPUT_DIR}"
    local dry_run="false"
    local verbose="false"
    local auto_discover="${AUTO_DISCOVER}"
    local custom_files=""
    local files=()
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                workshop_file="$2"
                auto_discover="false"
                shift 2
                ;;
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            --files)
                custom_files="$2"
                auto_discover="false"
                shift 2
                ;;
            --auto-discover)
                auto_discover="true"
                shift
                ;;
            --no-auto-discover)
                auto_discover="false"
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
    OUTPUT_DIR="${output_dir}"
    AUTO_DISCOVER="${auto_discover}"
    
    # Determine which files to process
    if [[ -n "${custom_files}" ]]; then
        # Process comma-separated file list
        IFS=',' read -ra file_list <<< "${custom_files}"
        for file in "${file_list[@]}"; do
            # Convert relative paths to absolute
            if [[ "${file}" != /* ]]; then
                file="${REPO_ROOT}/${file}"
            fi
            files+=("${file}")
        done
        log "Using custom file list: ${#files[@]} file(s)"
        
    elif [[ -n "${workshop_file}" ]]; then
        # Process single specified file
        if [[ "${workshop_file}" != /* ]]; then
            workshop_file="${REPO_ROOT}/${workshop_file}"
        fi
        files=("${workshop_file}")
        log "Using single specified file: $(basename "${workshop_file}")"
        
    elif [[ "${auto_discover}" == "true" ]]; then
        # Auto-discover files
        while IFS= read -r line; do
            files+=("${line}")
        done < <(discover_workshop_files)
        
        if [[ ${#files[@]} -eq 0 ]]; then
            error "No workshop details files found for auto-discovery"
            error "Expected files like: workshop_details.txt, workshop_details2.txt, etc."
            exit 1
        fi
        log "Auto-discovered ${#files[@]} file(s)"
        
    else
        error "No files specified and auto-discovery disabled"
        error "Use -f FILE, --files FILE1,FILE2, or --auto-discover"
        exit 1
    fi
    
    # Run the parsing process
    check_prerequisites "${files[@]}"
    
    if [[ "${dry_run}" == "false" ]]; then
        create_output_directory
    fi
    
    local user_count
    user_count=$(parse_workshop_details "${dry_run}" "${verbose}" "${files[@]}")
    
    show_summary "${user_count}" "${dry_run}"
}

main "$@"