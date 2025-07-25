#!/bin/bash

# Update Bearer Tokens Script
# Extracts bearer tokens from workshop_details files and updates .env files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
USER_ENV_DIR="${REPO_ROOT}/user_environments"

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
Update Bearer Tokens from Workshop Details

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -d, --directory DIR     User environments directory (default: user_environments)
    -f, --files PATTERN     Workshop details file pattern (default: workshop_details*.txt)
    -u, --users RANGE       User range (e.g., 1-5, 3,7,9, or single number)
    --dry-run               Show what would be updated without modifying files
    -v, --verbose           Verbose output
    -h, --help              Show this help

DESCRIPTION:
    This script extracts openshift_bearer_token values from workshop_details*.txt files
    and updates the corresponding .env files with the bearer tokens. This enables
    automatic login to individual user clusters without manual credential entry.

    The script:
    1. Parses workshop_details*.txt files to extract bearer tokens
    2. Matches tokens to users based on email addresses
    3. Updates OCP_BEARER_TOKEN in corresponding .env files
    4. Provides detailed logging of updates

EXAMPLES:
    $0                          # Update all users with available bearer tokens
    $0 -u 1-10                  # Update users 1-10 only
    $0 --dry-run -v             # Preview updates with verbose output
    $0 -f workshop_details1.txt # Use specific workshop details file

EOF
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
        error "Invalid user range format: $range"
        return 1
    fi
    
    # Sort and deduplicate
    printf '%s\n' "${users[@]}" | sort -n | uniq
}

# Discover all workshop_details files
discover_workshop_files() {
    local files=()
    local pattern="$1"
    
    for file in ${REPO_ROOT}/${pattern}; do
        if [[ -f "$file" ]]; then
            files+=("$file")
        fi
    done
    
    # Sort files to ensure consistent processing order
    if [[ ${#files[@]} -gt 0 ]]; then
        printf '%s\n' "${files[@]}" | sort
    fi
}

# Extract user data from workshop_details file
extract_user_data() {
    local workshop_file="$1"
    local verbose="$2"
    
    if [[ "$verbose" == "true" ]]; then
        log "Parsing workshop details file: $workshop_file"
    fi
    
    # Use Python for more reliable parsing
    python3 -c "
import re
import sys

def parse_workshop_file(filename):
    with open(filename, 'r') as f:
        content = f.read()
    
    # Split by service sections
    sections = re.split(r'^enterprise\.aap-product-demos[^\n]*$', content, flags=re.MULTILINE)
    
    results = []
    for section in sections[1:]:  # Skip first empty section
        # Find email address
        email_match = re.search(r'([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})', section)
        if not email_match:
            continue
        
        email = email_match.group(1).strip()
        
        # Find bearer token
        token_match = re.search(r'openshift_bearer_token:\s*([^\s\n]+)', section)
        if not token_match:
            continue
        
        token = token_match.group(1).strip()
        
        # Find GUID
        guid_match = re.search(r'guid:\s*([^\s\n]+)', section)
        guid = guid_match.group(1).strip() if guid_match else ''
        
        # Find API URL
        api_match = re.search(r'openshift_api_url:\s*([^\s\n]+)', section)
        api_url = api_match.group(1).strip() if api_match else ''
        
        results.append(f'{email}|{token}|{guid}|{api_url}')
    
    return results

if __name__ == '__main__':
    filename = sys.argv[1] if len(sys.argv) > 1 else None
    if filename:
        results = parse_workshop_file(filename)
        for result in results:
            print(result)
" "$workshop_file"
}

# Update .env file with bearer token
update_env_file() {
    local env_file="$1"
    local bearer_token="$2"
    local dry_run="$3"
    local verbose="$4"
    
    if [[ ! -f "$env_file" ]]; then
        error "Environment file not found: $env_file"
        return 1
    fi
    
    # Check if token already exists and is different
    local current_token=""
    if grep -q "^OCP_BEARER_TOKEN=" "$env_file"; then
        current_token=$(grep "^OCP_BEARER_TOKEN=" "$env_file" | cut -d'=' -f2)
    fi
    
    if [[ "$current_token" == "$bearer_token" ]]; then
        if [[ "$verbose" == "true" ]]; then
            log "Bearer token already up to date in: $(basename "$env_file")"
        fi
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        log "DRY RUN: Would update bearer token in: $(basename "$env_file")"
        if [[ "$verbose" == "true" ]]; then
            log "  Current: ${current_token:-"(empty)"}"
            log "  New: $bearer_token"
        fi
        return 0
    fi
    
    # Create backup
    cp "$env_file" "${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update or add bearer token
    if grep -q "^OCP_BEARER_TOKEN=" "$env_file"; then
        # Update existing token
        sed -i.tmp "s/^OCP_BEARER_TOKEN=.*/OCP_BEARER_TOKEN=$bearer_token/" "$env_file"
        rm -f "${env_file}.tmp"
    else
        # Add new token after the OCP_API_URL line
        sed -i.tmp "/^OCP_API_URL=/a\\
OCP_BEARER_TOKEN=$bearer_token" "$env_file"
        rm -f "${env_file}.tmp"
    fi
    
    if [[ "$verbose" == "true" ]]; then
        success "Updated bearer token in: $(basename "$env_file")"
        log "  Previous: ${current_token:-"(none)"}"
        log "  New: $bearer_token"
    else
        success "Updated: $(basename "$env_file")"
    fi
}

# Main processing function
process_bearer_tokens() {
    local user_env_dir="$1"
    local workshop_pattern="$2"
    local user_range="$3"
    local dry_run="$4"
    local verbose="$5"
    
    log "Discovering workshop details files..."
    local workshop_files
    workshop_files=$(discover_workshop_files "$workshop_pattern")
    
    if [[ -z "$workshop_files" ]]; then
        error "No workshop details files found matching pattern: $workshop_pattern"
        return 1
    fi
    
    local file_count
    file_count=$(echo "$workshop_files" | wc -l)
    log "Found $file_count workshop details file(s)"
    
    # Extract all user data from workshop files
    local user_data_file
    user_data_file=$(mktemp)
    
    while IFS= read -r workshop_file; do
        if [[ "$verbose" == "true" ]]; then
            log "Processing: $(basename "$workshop_file")"
        fi
        extract_user_data "$workshop_file" "$verbose" >> "$user_data_file"
    done <<< "$workshop_files"
    
    local total_tokens
    total_tokens=$(wc -l < "$user_data_file")
    log "Extracted $total_tokens bearer tokens from workshop details"
    
    # Get list of users to process
    local users=()
    if [[ -n "$user_range" ]]; then
        local user_list
        user_list=$(parse_user_range "$user_range")
        while IFS= read -r line; do
            [[ -n "$line" ]] && users+=("$line")
        done <<< "$user_list"
    else
        # Auto-detect all users
        for env_file in "$user_env_dir"/.env[0-9][0-9]; do
            if [[ -f "$env_file" ]]; then
                local user_num
                user_num=$(basename "$env_file" | sed 's/\.env0*//')
                users+=("$user_num")
            fi
        done
    fi
    
    if [[ ${#users[@]} -eq 0 ]]; then
        error "No users found to process"
        rm -f "$user_data_file"
        return 1
    fi
    
    log "Processing ${#users[@]} user environment(s)"
    
    local updated=0
    local skipped=0
    local failed=0
    
    # Process each user
    for user_num in "${users[@]}"; do
        local user_num_padded
        user_num_padded=$(printf "%02d" "$user_num")
        local env_file="${user_env_dir}/.env${user_num_padded}"
        
        if [[ ! -f "$env_file" ]]; then
            if [[ "$verbose" == "true" ]]; then
                warning "Environment file not found for user $user_num_padded: $env_file"
            fi
            ((failed++))
            continue
        fi
        
        # Get user email from env file
        local user_email
        if ! user_email=$(grep "^USER_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2); then
            warning "Could not find USER_EMAIL in $env_file"
            ((failed++))
            continue
        fi
        
        # Find matching bearer token
        local bearer_token=""
        while IFS='|' read -r email token guid api_url; do
            if [[ "$email" == "$user_email" ]]; then
                bearer_token="$token"
                break
            fi
        done < "$user_data_file"
        
        if [[ -z "$bearer_token" ]]; then
            if [[ "$verbose" == "true" ]]; then
                warning "No bearer token found for user $user_num_padded ($user_email)"
            fi
            ((skipped++))
            continue
        fi
        
        # Update the environment file
        if update_env_file "$env_file" "$bearer_token" "$dry_run" "$verbose"; then
            ((updated++))
        else
            ((failed++))
        fi
    done
    
    # Clean up
    rm -f "$user_data_file"
    
    # Summary
    echo
    echo "================================="
    echo "  BEARER TOKEN UPDATE SUMMARY"
    echo "================================="
    echo "Total Users Processed: ${#users[@]}"
    echo "Updated:              $updated"
    echo "Skipped:              $skipped"
    echo "Failed:               $failed"
    echo
    
    if [[ "$dry_run" == "true" ]]; then
        log "This was a dry run - no files were modified"
    elif [[ $updated -gt 0 ]]; then
        success "Successfully updated $updated user environment(s) with bearer tokens"
        log "Backup files created with timestamp suffix"
    fi
    
    return $(( failed > 0 ? 1 : 0 ))
}

main() {
    local user_env_dir="$USER_ENV_DIR"
    local workshop_pattern="workshop_details*.txt"
    local user_range=""
    local dry_run="false"
    local verbose="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--directory)
                user_env_dir="$2"
                shift 2
                ;;
            -f|--files)
                workshop_pattern="$2"
                shift 2
                ;;
            -u|--users)
                user_range="$2"
                shift 2
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
    
    # Validate user environment directory
    if [[ ! -d "$user_env_dir" ]]; then
        error "User environments directory not found: $user_env_dir"
        exit 1
    fi
    
    # Check for .env files
    local env_files
    env_files=$(find "$user_env_dir" -name ".env[0-9][0-9]" -type f | wc -l)
    if [[ $env_files -eq 0 ]]; then
        error "No user environment files found in $user_env_dir"
        error "Expected files like .env01, .env02, etc."
        exit 1
    fi
    
    log "Found $env_files user environment file(s) in $user_env_dir"
    
    # Process bearer tokens
    if process_bearer_tokens "$user_env_dir" "$workshop_pattern" "$user_range" "$dry_run" "$verbose"; then
        exit 0
    else
        exit 1
    fi
}

main "$@"