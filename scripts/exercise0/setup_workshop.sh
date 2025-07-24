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
    
    # Function to extract value for a given key from the structured format
    extract_value() {
        local key="$1"
        awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            getline
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
        }' "${DETAILS_FILE}"
    }
    
    # Extract credentials and URLs using the new structured format
    local aap_url=$(extract_value "aap_controller_web_url")
    local aap_user=$(extract_value "aap_controller_admin_user")
    local aap_password=$(extract_value "aap_controller_admin_password")
    local aap_token=$(extract_value "aap_controller_token")
    local ssh_host=$(extract_value "bastion_public_hostname")
    local ssh_port=$(extract_value "bastion_ssh_port")
    local ssh_user=$(extract_value "bastion_ssh_user_name")
    local ssh_password=$(extract_value "bastion_ssh_password")
    local console_url=$(extract_value "openshift_console_url")
    local api_url=$(extract_value "openshift_api_url")
    local bearer_token=$(extract_value "openshift_bearer_token")
    local oc_download_url=$(extract_value "openshift_client_download_url")
    local cluster_domain=$(extract_value "openshift_cluster_ingress_domain")
    local guid=$(extract_value "guid")
    local kubeadmin_password=$(extract_value "openshift_kubeadmin_password")
    
    # Set default values for missing fields
    local aws_key=""
    local aws_secret=""
    local domain="${cluster_domain}"
    
    # Write environment variables to .env file
    cat > "${ENV_FILE}" << EOF
# Workshop Environment Configuration
# Generated from details.txt on $(date)

# AWS Credentials (if available)
AWS_ACCESS_KEY_ID=${aws_key}
AWS_SECRET_ACCESS_KEY=${aws_secret}

# OpenShift Configuration
OCP_CONSOLE_URL=${console_url}
OCP_API_URL=${api_url}
OCP_BEARER_TOKEN=${bearer_token}
OCP_CLIENT_DOWNLOAD_URL=${oc_download_url}
OCP_CLUSTER_DOMAIN=${cluster_domain}
OCP_KUBEADMIN_PASSWORD=${kubeadmin_password}
ROUTE53_DOMAIN=${domain}

# Workshop Configuration
WORKSHOP_GUID=${guid}

# Automation Controller Configuration
AAP_URL=${aap_url}
AAP_USERNAME=${aap_user}
AAP_PASSWORD=${aap_password}
AAP_TOKEN=${aap_token}

# SSH Bastion Access
SSH_HOST=${ssh_host}
SSH_PORT=${ssh_port}
SSH_USER=${ssh_user}
SSH_PASSWORD=${ssh_password}
EOF

    log "Environment configuration written to .env"
}

configure_oc_login() {
    log "Configuring OpenShift CLI access..."
    
    source "${ENV_FILE}"
    
    if [[ -n "${OCP_BEARER_TOKEN}" ]]; then
        log "Logging into OpenShift using bearer token..."
        if oc login "${OCP_API_URL}" --token="${OCP_BEARER_TOKEN}" --insecure-skip-tls-verify=true; then
            log "Successfully logged into OpenShift cluster"
            log "Current user: $(oc whoami)"
            log "Current project: $(oc project -q)"
        else
            log "WARNING: Failed to login with bearer token"
            log "Please manually login: oc login ${OCP_API_URL}"
        fi
    else
        log "No bearer token found in details.txt"
        log "Please manually login to OpenShift cluster:"
        log "  oc login ${OCP_API_URL}"
        log "You may need to use a service account token or other authentication method"
    fi
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

# AAP API Helper Functions
aap_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    source "${ENV_FILE}"
    
    local auth_header=""
    if [[ -n "${AAP_TOKEN}" ]]; then
        auth_header="Authorization: Bearer ${AAP_TOKEN}"
    else
        auth_header="Authorization: Basic $(echo -n "${AAP_USERNAME}:${AAP_PASSWORD}" | base64)"
    fi
    
    local curl_opts=(
        -k -s
        -X "${method}"
        -H "Content-Type: application/json"
        -H "${auth_header}"
    )
    
    if [[ -n "${data}" ]]; then
        curl_opts+=(-d "${data}")
    fi
    
    curl "${curl_opts[@]}" "${AAP_URL}/api/controller/v2${endpoint}"
}

setup_aap_project() {
    log "Setting up AAP project for workshop exercises..."
    
    source "${ENV_FILE}"
    
    # Project configuration - Update SCM URL to actual workshop repository
    local project_name="AAP-Workshop-${WORKSHOP_GUID}"
    local project_data=$(cat << EOF
{
    "name": "${project_name}",
    "description": "AAP Workshop Exercise Playbooks - Advanced AAP 2.5 with OpenShift Integration",
    "scm_type": "git",
    "scm_url": "https://github.com/your-org/AAP-with-OCP-Workshop.git",
    "scm_branch": "main",
    "organization": 1,
    "scm_update_on_launch": true,
    "scm_update_cache_timeout": 0,
    "allow_override": false,
    "timeout": 0
}
EOF
    )
    
    # Check if project already exists
    local existing_project=$(aap_api_call "GET" "/projects/?name=${project_name}" "")
    if echo "${existing_project}" | grep -q "\"count\":0"; then
        log "Creating new AAP project: ${project_name}"
        local create_result=$(aap_api_call "POST" "/projects/" "${project_data}")
        if echo "${create_result}" | grep -q "\"id\""; then
            log "Successfully created AAP project"
            # Store project ID for later use
            local project_id=$(echo "${create_result}" | grep -o '"id":[0-9]*' | cut -d':' -f2)
            echo "AAP_PROJECT_ID=${project_id}" >> "${ENV_FILE}"
        else
            log "WARNING: Failed to create AAP project: ${create_result}"
            return 1
        fi
    else
        log "AAP project already exists: ${project_name}"
        local project_id=$(echo "${existing_project}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        echo "AAP_PROJECT_ID=${project_id}" >> "${ENV_FILE}"
    fi
}

setup_aap_inventory() {
    log "Setting up AAP inventory for workshop..."
    
    source "${ENV_FILE}"
    
    local inventory_name="Workshop-OpenShift-${WORKSHOP_GUID}"
    local inventory_data=$(cat << EOF
{
    "name": "${inventory_name}",
    "description": "OpenShift cluster inventory for AAP workshop",
    "organization": 1,
    "variables": "---\nopenshift_cluster_domain: ${OCP_CLUSTER_DOMAIN}\nworkshop_guid: ${WORKSHOP_GUID}\nworkshop_environment: dev"
}
EOF
    )
    
    # Check if inventory already exists
    local existing_inventory=$(aap_api_call "GET" "/inventories/?name=${inventory_name}" "")
    if echo "${existing_inventory}" | grep -q "\"count\":0"; then
        log "Creating new AAP inventory: ${inventory_name}"
        local create_result=$(aap_api_call "POST" "/inventories/" "${inventory_data}")
        if echo "${create_result}" | grep -q "\"id\""; then
            log "Successfully created AAP inventory"
            local inventory_id=$(echo "${create_result}" | grep -o '"id":[0-9]*' | cut -d':' -f2)
            echo "AAP_INVENTORY_ID=${inventory_id}" >> "${ENV_FILE}"
        else
            log "WARNING: Failed to create AAP inventory: ${create_result}"
            return 1
        fi
    else
        log "AAP inventory already exists: ${inventory_name}"
        local inventory_id=$(echo "${existing_inventory}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        echo "AAP_INVENTORY_ID=${inventory_id}" >> "${ENV_FILE}"
    fi
}

setup_aap_credential() {
    log "Setting up AAP OpenShift credential..."
    
    source "${ENV_FILE}"
    
    local credential_name="OpenShift-${WORKSHOP_GUID}"
    local credential_data=$(cat << EOF
{
    "name": "${credential_name}",
    "description": "OpenShift cluster credentials for workshop",
    "organization": 1,
    "credential_type": 17,
    "inputs": {
        "host": "${OCP_API_URL}",
        "bearer_token": "${OCP_BEARER_TOKEN}",
        "verify_ssl": false
    }
}
EOF
    )
    
    # Check if credential already exists
    local existing_credential=$(aap_api_call "GET" "/credentials/?name=${credential_name}" "")
    if echo "${existing_credential}" | grep -q "\"count\":0"; then
        log "Creating new AAP OpenShift credential: ${credential_name}"
        local create_result=$(aap_api_call "POST" "/credentials/" "${credential_data}")
        if echo "${create_result}" | grep -q "\"id\""; then
            log "Successfully created AAP credential"
            local credential_id=$(echo "${create_result}" | grep -o '"id":[0-9]*' | cut -d':' -f2)
            echo "AAP_CREDENTIAL_ID=${credential_id}" >> "${ENV_FILE}"
        else
            log "WARNING: Failed to create AAP credential: ${create_result}"
            return 1
        fi
    else
        log "AAP credential already exists: ${credential_name}"
        local credential_id=$(echo "${existing_credential}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        echo "AAP_CREDENTIAL_ID=${credential_id}" >> "${ENV_FILE}"
    fi
}

setup_aap_job_templates() {
    log "Setting up AAP job templates for workshop exercises..."
    
    source "${ENV_FILE}"
    
    # Define job templates for each module
    local job_templates=(
        "Module1-Dynamic-Inventory:playbooks/module1/exercise1-1-basic-inventory.yml:Dynamic inventory discovery and management"
        "Module1-Multi-Cluster:playbooks/module1/exercise1-2-test-multi-cluster.yml:Multi-cluster inventory testing"
        "Module1-Advanced-Grouping:playbooks/module1/exercise1-3-advanced-grouping.yml:Advanced inventory grouping patterns"
        "Module1-Troubleshooting:playbooks/module1/exercise1-4-troubleshooting.yml:Inventory troubleshooting and optimization"
        "Module2-RBAC-Setup:playbooks/module2/exercise2-1-rbac-setup.yml:RBAC setup and configuration"
        "Module2-RBAC-Automation:playbooks/module2/exercise2-2-rbac-automation.yml:Automated RBAC management"
        "Module2-Idempotent-Deploy:playbooks/module2/exercise2-3-idempotent-deployment.yml:Idempotent resource deployment"
        "Module3-Template-Engine:playbooks/module3/exercise3-1-template-engine.yml:Advanced Jinja2 templating"
        "Module3-Error-Handling:playbooks/module3/exercise3-2-error-handling.yml:Comprehensive error handling"
        "Module3-Troubleshooting:playbooks/module3/exercise3-3-troubleshooting.yml:Advanced troubleshooting automation"
    )
    
    for template_config in "${job_templates[@]}"; do
        IFS=':' read -r template_name playbook_path description <<< "$template_config"
        
        local job_template_data=$(cat << EOF
{
    "name": "${template_name}-${WORKSHOP_GUID}",
    "description": "${description}",
    "job_type": "run",
    "inventory": ${AAP_INVENTORY_ID},
    "project": ${AAP_PROJECT_ID},
    "playbook": "${playbook_path}",
    "credentials": [${AAP_CREDENTIAL_ID}],
    "execution_environment": ${AAP_EE_ID:-null},
    "verbosity": 1,
    "ask_variables_on_launch": true,
    "ask_limit_on_launch": false,
    "ask_tags_on_launch": false,
    "ask_skip_tags_on_launch": false,
    "ask_job_type_on_launch": false,
    "ask_verbosity_on_launch": false,
    "ask_inventory_on_launch": false,
    "ask_credential_on_launch": false,
    "survey_enabled": false,
    "become_enabled": false,
    "diff_mode": false,
    "allow_simultaneous": false,
    "job_slice_count": 1,
    "timeout": 0,
    "use_fact_cache": false
}
EOF
        )
        
        # Check if job template already exists
        local existing_template=$(aap_api_call "GET" "/job_templates/?name=${template_name}-${WORKSHOP_GUID}" "")
        if echo "${existing_template}" | grep -q "\"count\":0"; then
            log "Creating job template: ${template_name}-${WORKSHOP_GUID}"
            local create_result=$(aap_api_call "POST" "/job_templates/" "${job_template_data}")
            if echo "${create_result}" | grep -q "\"id\""; then
                log "Successfully created job template: ${template_name}"
            else
                log "WARNING: Failed to create job template ${template_name}: ${create_result}"
            fi
        else
            log "Job template already exists: ${template_name}-${WORKSHOP_GUID}"
        fi
    done
}

setup_aap_resources() {
    log "Setting up AAP resources for workshop..."
    
    # Set up the project first
    if ! setup_aap_project; then
        log "ERROR: Failed to set up AAP project, skipping remaining AAP setup"
        return 1
    fi
    
    # Set up inventory
    if ! setup_aap_inventory; then
        log "ERROR: Failed to set up AAP inventory, skipping job templates"
        return 1
    fi
    
    # Set up credentials
    if ! setup_aap_credential; then
        log "ERROR: Failed to set up AAP credentials, skipping job templates"
        return 1
    fi
    
    # Set up job templates
    setup_aap_job_templates
    
    log "AAP resources setup completed"
}

# Execution Environment Functions
check_ee_prerequisites() {
    log "Checking execution environment prerequisites..."
    
    # Check for ansible-builder
    if ! command -v ansible-builder &> /dev/null; then
        log "WARNING: ansible-builder not found. Installing via pip..."
        pip install ansible-builder || {
            log "ERROR: Failed to install ansible-builder"
            return 1
        }
    fi
    
    # Check for container runtime (podman or docker)
    if command -v podman &> /dev/null; then
        export CONTAINER_RUNTIME="podman"
    elif command -v docker &> /dev/null; then
        export CONTAINER_RUNTIME="docker"
    else
        log "ERROR: Neither podman nor docker found. Please install a container runtime."
        return 1
    fi
    
    log "Using container runtime: ${CONTAINER_RUNTIME}"
    return 0
}

build_execution_environment() {
    log "Building custom execution environment..."
    
    source "${ENV_FILE}"
    local ee_dir="${REPO_ROOT}/execution-environment"
    local ee_name="aap-workshop-ee"
    local ee_tag="${WORKSHOP_GUID:-latest}"
    local ee_full_name="${ee_name}:${ee_tag}"
    
    if [[ ! -d "${ee_dir}" ]]; then
        log "ERROR: Execution environment directory not found: ${ee_dir}"
        return 1
    fi
    
    # Change to EE directory
    cd "${ee_dir}"
    
    # Build the execution environment
    log "Building execution environment: ${ee_full_name}"
    if ansible-builder build -t "${ee_full_name}" .; then
        log "Successfully built execution environment: ${ee_full_name}"
        echo "EE_IMAGE_NAME=${ee_full_name}" >> "${ENV_FILE}"
        return 0
    else
        log "ERROR: Failed to build execution environment"
        return 1
    fi
}

setup_aap_execution_environment() {
    log "Setting up execution environment in AAP Controller..."
    
    source "${ENV_FILE}"
    
    local ee_name="Workshop-EE-${WORKSHOP_GUID}"
    local ee_image="${EE_IMAGE_NAME:-aap-workshop-ee:${WORKSHOP_GUID}}"
    
    # For now, we'll assume the image is available locally or in a registry
    # In a real deployment, you'd push to a registry accessible by AAP
    local ee_data=$(cat << EOF
{
    "name": "${ee_name}",
    "description": "Custom execution environment for AAP Workshop with kubernetes.core collection",
    "organization": 1,
    "image": "${ee_image}",
    "pull": "missing",
    "credential": null
}
EOF
    )
    
    # Check if execution environment already exists
    local existing_ee=$(aap_api_call "GET" "/execution_environments/?name=${ee_name}" "")
    if echo "${existing_ee}" | grep -q "\"count\":0"; then
        log "Creating new AAP execution environment: ${ee_name}"
        local create_result=$(aap_api_call "POST" "/execution_environments/" "${ee_data}")
        if echo "${create_result}" | grep -q "\"id\""; then
            log "Successfully created AAP execution environment"
            local ee_id=$(echo "${create_result}" | grep -o '"id":[0-9]*' | cut -d':' -f2)
            echo "AAP_EE_ID=${ee_id}" >> "${ENV_FILE}"
        else
            log "WARNING: Failed to create AAP execution environment: ${create_result}"
            return 1
        fi
    else
        log "AAP execution environment already exists: ${ee_name}"
        local ee_id=$(echo "${existing_ee}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        echo "AAP_EE_ID=${ee_id}" >> "${ENV_FILE}"
    fi
}

setup_execution_environment() {
    log "Setting up execution environment for workshop..."
    
    # Check prerequisites
    if ! check_ee_prerequisites; then
        log "WARNING: Execution environment prerequisites not met, skipping EE setup"
        return 1
    fi
    
    # Build the execution environment
    if ! build_execution_environment; then
        log "WARNING: Failed to build execution environment, skipping AAP EE setup"
        return 1
    fi
    
    # Set up in AAP Controller
    if ! setup_aap_execution_environment; then
        log "WARNING: Failed to set up execution environment in AAP"
        return 1
    fi
    
    log "Execution environment setup completed"
}

main() {
    log "Starting Exercise 0: Workshop Environment Setup"
    
    check_prerequisites
    parse_details
    configure_oc_login
    create_namespace
    verify_aap_access
    
    # Set up AAP resources if AAP is accessible
    source "${ENV_FILE}"
    if curl -k -s --connect-timeout 10 "${AAP_URL}/api/v2/ping/" >/dev/null; then
        # Set up execution environment first
        setup_execution_environment
        
        # Set up AAP resources (will use the execution environment if available)
        setup_aap_resources
    else
        log "WARNING: AAP not accessible, skipping AAP resource setup"
        log "You can run AAP setup manually later if needed"
    fi
    
    log "Exercise 0 setup completed successfully!"
    log ""
    log "Workshop Environment Summary:"
    log "  OpenShift Cluster: ${OCP_API_URL}"
    log "  Workshop Namespace: workshop-aap"
    log "  AAP Controller: ${AAP_URL}"
    log "  Workshop GUID: ${WORKSHOP_GUID}"
    log ""
    log "Next steps:"
    log "  1. Ensure you are logged into OpenShift: oc whoami"
    log "  2. Access AAP Controller and verify job templates are created"
    log "  3. Run the setup playbook: ansible-playbook playbooks/exercise0/setup.yml"
    log "  4. Validate the setup: ./scripts/exercise0/validate_setup.sh"
}

main "$@"