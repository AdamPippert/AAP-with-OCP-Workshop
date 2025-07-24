#!/bin/bash

# Exercise 0: Workshop Environment Setup
# Parses details.txt and configures the workshop environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DETAILS_FILE="${REPO_ROOT}/details.txt"
ENV_FILE="${REPO_ROOT}/.env"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    if [[ ! -f "${DETAILS_FILE}" ]]; then
        error "details.txt file not found. Please ensure it's populated by the workshop moderator."
    fi
    
    command -v oc >/dev/null 2>&1 || error "OpenShift CLI (oc) not found. Please install it first."
    command -v ansible-playbook >/dev/null 2>&1 || error "Ansible not found. Please install it first."
}

parse_details() {
    log "Parsing details.txt for environment configuration..."
    
    # Extract credentials and URLs using grep and sed
    local aws_key=$(grep "AWS_ACCESS_KEY_ID:" "${DETAILS_FILE}" | sed 's/.*AWS_ACCESS_KEY_ID: //')
    local aws_secret=$(grep "AWS_SECRET_ACCESS_KEY:" "${DETAILS_FILE}" | sed 's/.*AWS_SECRET_ACCESS_KEY: //')
    local domain=$(grep "Top level route53 domain:" "${DETAILS_FILE}" | sed 's/.*Top level route53 domain: //')
    local console_url=$(grep "OpenShift Console:" "${DETAILS_FILE}" | sed 's/.*OpenShift Console: //')
    local api_url=$(grep "OpenShift API for command line" "${DETAILS_FILE}" | sed 's/.*client: //')
    local aap_url=$(grep "Automation Controller URL:" "${DETAILS_FILE}" | sed 's/.*Automation Controller URL: //')
    local aap_user=$(grep "Automation Controller Admin Login:" "${DETAILS_FILE}" | sed 's/.*Automation Controller Admin Login: //')
    local aap_password=$(grep "Automation Controller Admin Password:" "${DETAILS_FILE}" | sed 's/.*Automation Controller Admin Password: //')
    local ssh_host=$(grep "ssh lab-user@" "${DETAILS_FILE}" | head -1 | sed 's/.*ssh lab-user@//' | sed 's/ -p.*//')
    local ssh_port=$(grep "ssh lab-user@" "${DETAILS_FILE}" | head -1 | sed 's/.*-p //')
    local ssh_password=$(grep "ssh password when prompted:" "${DETAILS_FILE}" | sed 's/.*ssh password when prompted: //')
    
    # Write environment variables to .env file
    cat > "${ENV_FILE}" << EOF
# Workshop Environment Configuration
# Generated from details.txt on $(date)

# AWS Credentials
AWS_ACCESS_KEY_ID=${aws_key}
AWS_SECRET_ACCESS_KEY=${aws_secret}

# OpenShift Configuration
OCP_CONSOLE_URL=${console_url}
OCP_API_URL=${api_url}
ROUTE53_DOMAIN=${domain}

# Automation Controller Configuration
AAP_URL=${aap_url}
AAP_USERNAME=${aap_user}
AAP_PASSWORD=${aap_password}

# SSH Access
SSH_HOST=${ssh_host}
SSH_PORT=${ssh_port}
SSH_PASSWORD=${ssh_password}
SSH_USER=lab-user
EOF

    log "Environment configuration written to .env"
}

configure_oc_login() {
    log "Configuring OpenShift CLI access..."
    
    source "${ENV_FILE}"
    
    # Note: In a real workshop, participants would use proper authentication
    # This assumes service account tokens or other auth methods are configured
    log "Please ensure you are logged into OpenShift cluster:"
    log "  oc login ${OCP_API_URL}"
    log "You may need to use a service account token or other authentication method"
}

create_namespace() {
    log "Creating workshop namespace..."
    
    # Create workshop namespace if it doesn't exist
    if ! oc get namespace workshop-aap 2>/dev/null; then
        oc create namespace workshop-aap
        log "Created workshop-aap namespace"
    else
        log "Workshop namespace already exists"
    fi
}

verify_aap_access() {
    log "Verifying Automation Controller access..."
    
    source "${ENV_FILE}"
    
    # Test AAP connectivity (basic curl test)
    if curl -k -s --connect-timeout 10 "${AAP_URL}/api/v2/ping/" >/dev/null; then
        log "Automation Controller is accessible"
    else
        log "WARNING: Cannot reach Automation Controller at ${AAP_URL}"
        log "Please verify the URL and network connectivity"
    fi
}

main() {
    log "Starting Exercise 0: Workshop Environment Setup"
    
    check_prerequisites
    parse_details
    configure_oc_login
    create_namespace
    verify_aap_access
    
    log "Exercise 0 setup completed successfully!"
    log "Next steps:"
    log "  1. Ensure you are logged into OpenShift: oc whoami"
    log "  2. Run the setup playbook: ansible-playbook playbooks/exercise0/setup.yml"
    log "  3. Validate the setup: ./scripts/exercise0/validate_setup.sh"
}

main "$@"