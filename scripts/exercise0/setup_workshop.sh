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

clean_env_file() {
    # Remove any invalid lines from .env file that don't match KEY=VALUE pattern
    if [[ -f "${ENV_FILE}" ]]; then
        log "Cleaning .env file of invalid entries..."
        local temp_file=$(mktemp)
        
        # Keep only lines that are comments, empty, or valid KEY=VALUE pairs
        grep -E '^[[:space:]]*$|^[[:space:]]*#|^[[:space:]]*[A-Z_][A-Z0-9_]*=.*$' "${ENV_FILE}" > "${temp_file}" || true
        
        # Replace original file if we have valid content
        if [[ -s "${temp_file}" ]]; then
            mv "${temp_file}" "${ENV_FILE}"
            log "Cleaned .env file"
        else
            log "WARNING: .env file appears to be completely invalid, keeping original"
            rm -f "${temp_file}"
        fi
    fi
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
            local project_id=$(echo "${create_result}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
            if [[ -n "${project_id}" && "${project_id}" =~ ^[0-9]+$ ]]; then
                echo "AAP_PROJECT_ID=${project_id}" >> "${ENV_FILE}"
                log "Stored project ID: ${project_id}"
            else
                log "WARNING: Could not extract valid project ID from response"
            fi
        else
            log "WARNING: Failed to create AAP project: ${create_result}"
            return 1
        fi
    else
        log "AAP project already exists: ${project_name}"
        local project_id=$(echo "${existing_project}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        if [[ -n "${project_id}" && "${project_id}" =~ ^[0-9]+$ ]]; then
            echo "AAP_PROJECT_ID=${project_id}" >> "${ENV_FILE}"
            log "Found existing project ID: ${project_id}"
        else
            log "WARNING: Could not extract valid project ID from existing project"
        fi
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
            local inventory_id=$(echo "${create_result}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
            if [[ -n "${inventory_id}" && "${inventory_id}" =~ ^[0-9]+$ ]]; then
                echo "AAP_INVENTORY_ID=${inventory_id}" >> "${ENV_FILE}"
                log "Stored inventory ID: ${inventory_id}"
            else
                log "WARNING: Could not extract valid inventory ID from response"
            fi
        else
            log "WARNING: Failed to create AAP inventory: ${create_result}"
            return 1
        fi
    else
        log "AAP inventory already exists: ${inventory_name}"
        local inventory_id=$(echo "${existing_inventory}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        if [[ -n "${inventory_id}" && "${inventory_id}" =~ ^[0-9]+$ ]]; then
            echo "AAP_INVENTORY_ID=${inventory_id}" >> "${ENV_FILE}"
            log "Found existing inventory ID: ${inventory_id}"
        else
            log "WARNING: Could not extract valid inventory ID from existing inventory"
        fi
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
            local credential_id=$(echo "${create_result}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
            if [[ -n "${credential_id}" && "${credential_id}" =~ ^[0-9]+$ ]]; then
                echo "AAP_CREDENTIAL_ID=${credential_id}" >> "${ENV_FILE}"
                log "Stored credential ID: ${credential_id}"
            else
                log "WARNING: Could not extract valid credential ID from response"
            fi
        else
            log "WARNING: Failed to create AAP credential: ${create_result}"
            return 1
        fi
    else
        log "AAP credential already exists: ${credential_name}"
        local credential_id=$(echo "${existing_credential}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        if [[ -n "${credential_id}" && "${credential_id}" =~ ^[0-9]+$ ]]; then
            echo "AAP_CREDENTIAL_ID=${credential_id}" >> "${ENV_FILE}"
            log "Found existing credential ID: ${credential_id}"
        else
            log "WARNING: Could not extract valid credential ID from existing credential"
        fi
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
    
    # Determine container registry based on OpenShift cluster
    local registry_host=""
    if [[ -n "${OCP_CLUSTER_DOMAIN}" ]]; then
        registry_host="default-route-openshift-image-registry.${OCP_CLUSTER_DOMAIN}"
        local registry_image="${registry_host}/workshop-aap/${ee_name}:${ee_tag}"
    else
        log "WARNING: No cluster domain found, using local image only"
        local registry_image="${ee_full_name}"
    fi
    
    if [[ ! -d "${ee_dir}" ]]; then
        log "ERROR: Execution environment directory not found: ${ee_dir}"
        return 1
    fi
    
    # Check ansible-builder version for compatibility
    local ab_version
    ab_version=$(ansible-builder --version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    log "Using ansible-builder version: ${ab_version}"
    
    # Check container runtime version
    local runtime_version
    runtime_version=$(${CONTAINER_RUNTIME:-podman} --version 2>/dev/null | head -1 || echo "unknown")
    log "Using container runtime: ${runtime_version}"
    
    # Change to EE directory
    cd "${ee_dir}"
    
    # Build the execution environment with verbose output and error handling
    log "Building execution environment: ${ee_full_name}"
    log "Build directory: ${ee_dir}"
    
    # Create a temporary log file for detailed output
    local build_log="/tmp/ee-build-${WORKSHOP_GUID:-$(date +%s)}.log"
    
    # Build with detailed logging
    log "Running: ansible-builder build -t ${ee_full_name} --verbosity 2 ."
    if ansible-builder build -t "${ee_full_name}" --verbosity 2 . 2>&1 | tee "${build_log}"; then
        log "Successfully built execution environment: ${ee_full_name}"
        
        # Verify the image was created
        if ${CONTAINER_RUNTIME:-podman} images -q "${ee_full_name}" >/dev/null 2>&1; then
            log "Verified execution environment image exists locally"
        else
            log "ERROR: Image was not created successfully"
            log "Build log contents:"
            cat "${build_log}" | tail -20
            return 1
        fi
        
        # Push to OpenShift internal registry if available
        if [[ -n "${registry_host}" ]]; then
            log "Pushing execution environment to OpenShift registry..."
            
            # Tag for registry
            if ${CONTAINER_RUNTIME:-podman} tag "${ee_full_name}" "${registry_image}"; then
                log "Tagged image for registry: ${registry_image}"
                
                # Create image stream in workshop namespace
                if oc get imagestream "${ee_name}" -n workshop-aap 2>/dev/null; then
                    log "Image stream already exists: ${ee_name}"
                else
                    if oc create imagestream "${ee_name}" -n workshop-aap; then
                        log "Created image stream: ${ee_name}"
                    else
                        log "WARNING: Failed to create image stream"
                    fi
                fi
                
                # Push to registry
                if ${CONTAINER_RUNTIME:-podman} push "${registry_image}"; then
                    log "Successfully pushed execution environment to registry"
                    echo "EE_REGISTRY_IMAGE=${registry_image}" >> "${ENV_FILE}"
                else
                    log "WARNING: Failed to push to registry, using local image"
                fi
            else
                log "WARNING: Failed to tag image for registry"
            fi
        fi
        
        echo "EE_IMAGE_NAME=${ee_full_name}" >> "${ENV_FILE}"
        echo "EE_REGISTRY_IMAGE=${registry_image:-${ee_full_name}}" >> "${ENV_FILE}"
        
        # Clean up build log on success
        rm -f "${build_log}"
        return 0
    else
        log "ERROR: Failed to build execution environment"
        log "Build log contents (last 50 lines):"
        cat "${build_log}" | tail -50
        log "Full build log saved to: ${build_log}"
        
        # Check for common issues
        if grep -q "TypeError.*not supported.*str.*int" "${build_log}"; then
            log "TROUBLESHOOTING: Version comparison error detected"
            log "This is often caused by incompatible package versions"
            log "Try upgrading ansible-builder: pip install --upgrade ansible-builder"
            log "Or check requirements.yml for version conflicts"
        fi
        
        if grep -q "registry.redhat.io" "${build_log}"; then
            log "TROUBLESHOOTING: Red Hat registry access issue"
            log "Ensure you have access to registry.redhat.io"
            log "Try: ${CONTAINER_RUNTIME:-podman} login registry.redhat.io"
        fi
        
        return 1
    fi
}

setup_aap_execution_environment() {
    log "Setting up execution environment in AAP Controller..."
    
    source "${ENV_FILE}"
    
    local ee_name="Workshop-EE-${WORKSHOP_GUID}"
    local ee_image="${EE_REGISTRY_IMAGE:-${EE_IMAGE_NAME:-aap-workshop-ee:${WORKSHOP_GUID}}}"
    
    # Determine pull policy based on image location
    local pull_policy="missing"
    if [[ "${ee_image}" == *"${OCP_CLUSTER_DOMAIN}"* ]]; then
        pull_policy="always"  # Always pull from OpenShift registry for fresh images
    fi
    
    local ee_data=$(cat << EOF
{
    "name": "${ee_name}",
    "description": "Custom execution environment for AAP Workshop with kubernetes.core and redhat.openshift collections",
    "organization": 1,
    "image": "${ee_image}",
    "pull": "${pull_policy}",
    "credential": null
}
EOF
    )
    
    # Check if execution environment already exists
    local existing_ee=$(aap_api_call "GET" "/execution_environments/?name=${ee_name}" "")
    if echo "${existing_ee}" | grep -q "\"count\":0"; then
        log "Creating new AAP execution environment: ${ee_name}"
        log "Using image: ${ee_image}"
        local create_result=$(aap_api_call "POST" "/execution_environments/" "${ee_data}")
        if echo "${create_result}" | grep -q "\"id\""; then
            log "Successfully created AAP execution environment"
            local ee_id=$(echo "${create_result}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
            if [[ -n "${ee_id}" && "${ee_id}" =~ ^[0-9]+$ ]]; then
                echo "AAP_EE_ID=${ee_id}" >> "${ENV_FILE}"
                log "Stored execution environment ID: ${ee_id}"
            else
                log "WARNING: Could not extract valid execution environment ID from response"
            fi
        else
            log "WARNING: Failed to create AAP execution environment: ${create_result}"
            return 1
        fi
    else
        log "AAP execution environment already exists: ${ee_name}"
        local ee_id=$(echo "${existing_ee}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        if [[ -n "${ee_id}" && "${ee_id}" =~ ^[0-9]+$ ]]; then
            echo "AAP_EE_ID=${ee_id}" >> "${ENV_FILE}"
            log "Found existing execution environment ID: ${ee_id}"
        else
            log "WARNING: Could not extract valid execution environment ID from existing EE"
        fi
        
        # Update existing EE with latest image
        log "Updating execution environment with latest image: ${ee_image}"
        local update_result=$(aap_api_call "PATCH" "/execution_environments/${ee_id}/" "{\"image\": \"${ee_image}\"}")
        if echo "${update_result}" | grep -q "\"id\""; then
            log "Successfully updated execution environment image"
        else
            log "WARNING: Failed to update execution environment image"
        fi
    fi
}

validate_execution_environment() {
    log "Validating execution environment availability..."
    
    source "${ENV_FILE}"
    
    # Check if image exists locally
    local ee_image="${EE_IMAGE_NAME:-aap-workshop-ee:${WORKSHOP_GUID}}"
    if ${CONTAINER_RUNTIME:-podman} images -q "${ee_image}" &> /dev/null; then
        log "Execution environment image found locally: ${ee_image}"
    else
        log "WARNING: Execution environment image not found locally"
        return 1
    fi
    
    # Test collections in the execution environment
    log "Testing kubernetes.core collection availability..."
    if ${CONTAINER_RUNTIME:-podman} run --rm "${ee_image}" ansible-galaxy collection list kubernetes.core &> /dev/null; then
        log "kubernetes.core collection is available in execution environment"
    else
        log "WARNING: kubernetes.core collection not found in execution environment"
        return 1
    fi
    
    log "Testing redhat.openshift collection availability..."
    if ${CONTAINER_RUNTIME:-podman} run --rm "${ee_image}" ansible-galaxy collection list redhat.openshift &> /dev/null; then
        log "redhat.openshift collection is available in execution environment"
    else
        log "WARNING: redhat.openshift collection not found in execution environment"
        return 1
    fi
    
    # Test OpenShift CLI availability
    log "Testing OpenShift CLI availability..."
    if ${CONTAINER_RUNTIME:-podman} run --rm "${ee_image}" oc version --client &> /dev/null; then
        log "OpenShift CLI is available in execution environment"
    else
        log "WARNING: OpenShift CLI not found in execution environment"
        return 1
    fi
    
    log "Execution environment validation completed successfully"
    return 0
}

use_published_execution_environment() {
    log "Using published execution environment..."
    
    source "${ENV_FILE}"
    
    # Load published EE configuration if available
    local published_config="${REPO_ROOT}/published-ee-config.env"
    if [[ -f "${published_config}" ]]; then
        log "Loading published execution environment configuration..."
        source "${published_config}"
    fi
    
    # Set default published image if not configured
    local published_image="${PUBLISHED_EE_IMAGE:-quay.io/aap-workshop/aap-workshop-ee:latest}"
    
    log "Using published execution environment: ${published_image}"
    
    # Pull the published image
    log "Pulling execution environment from registry..."
    if ${CONTAINER_RUNTIME:-podman} pull "${published_image}"; then
        log "Successfully pulled published execution environment"
        
        # Tag locally for consistency
        local local_tag="aap-workshop-ee:${WORKSHOP_GUID:-latest}"
        if ${CONTAINER_RUNTIME:-podman} tag "${published_image}" "${local_tag}"; then
            log "Tagged locally as: ${local_tag}"
        fi
        
        # Set environment variables
        echo "EE_IMAGE_NAME=${local_tag}" >> "${ENV_FILE}"
        echo "EE_REGISTRY_IMAGE=${published_image}" >> "${ENV_FILE}"
        
        return 0
    else
        log "ERROR: Failed to pull published execution environment"
        log "Falling back to building locally..."
        return 1
    fi
}

build_with_fallback_script() {
    log "Attempting fallback build using build script..."
    
    source "${ENV_FILE}"
    local ee_name="aap-workshop-ee"
    local ee_tag="${WORKSHOP_GUID:-latest}"
    local ee_full_name="${ee_name}:${ee_tag}"
    
    # Use the dedicated build script
    if [[ -x "${REPO_ROOT}/scripts/build_execution_environment.sh" ]]; then
        log "Using dedicated build script: ${REPO_ROOT}/scripts/build_execution_environment.sh"
        if "${REPO_ROOT}/scripts/build_execution_environment.sh" -n "${ee_name}" -t "${ee_tag}"; then
            log "Successfully built execution environment using fallback script"
            echo "EE_IMAGE_NAME=${ee_full_name}" >> "${ENV_FILE}"
            echo "EE_REGISTRY_IMAGE=${ee_full_name}" >> "${ENV_FILE}"
            return 0
        else
            log "ERROR: Fallback build script also failed"
            return 1
        fi
    else
        log "ERROR: Fallback build script not found or not executable"
        return 1
    fi
}

setup_execution_environment() {
    log "Setting up execution environment for workshop..."
    
    # Check if we should use published EE
    if [[ "${USE_PUBLISHED_EE:-false}" == "true" ]]; then
        if use_published_execution_environment; then
            log "Successfully configured published execution environment"
            
            # Set up in AAP Controller
            if ! setup_aap_execution_environment; then
                log "WARNING: Failed to set up execution environment in AAP"
                return 1
            fi
            
            log "Published execution environment setup completed successfully"
            return 0
        else
            log "Failed to use published execution environment, falling back to building locally"
        fi
    fi
    
    # Check prerequisites for building locally
    if ! check_ee_prerequisites; then
        log "WARNING: Execution environment prerequisites not met"
        log "Attempting to use published execution environment as fallback..."
        
        # Try published EE as fallback
        if use_published_execution_environment; then
            log "Successfully configured published execution environment as fallback"
            setup_aap_execution_environment
            return $?
        else
            log "ERROR: No execution environment available"
            return 1
        fi
    fi
    
    # Build the execution environment locally
    if ! build_execution_environment; then
        log "WARNING: Primary build method failed, trying fallback build script..."
        
        # Try fallback build method
        if build_with_fallback_script; then
            log "Fallback build succeeded"
        else
            log "WARNING: All build methods failed, trying published execution environment..."
            if use_published_execution_environment; then
                log "Successfully configured published execution environment as fallback"
            else
                log "ERROR: All execution environment setup methods failed"
                return 1
            fi
        fi
    fi
    
    # Validate the execution environment (skip if using published)
    if [[ "${USE_PUBLISHED_EE:-false}" != "true" ]]; then
        if ! validate_execution_environment; then
            log "WARNING: Execution environment validation failed"
            log "Proceeding anyway, but some workshop exercises may not work correctly"
        fi
    fi
    
    # Set up in AAP Controller
    if ! setup_aap_execution_environment; then
        log "WARNING: Failed to set up execution environment in AAP"
        return 1
    fi
    
    log "Execution environment setup completed successfully"
}

main() {
    log "Starting Exercise 0: Workshop Environment Setup"
    
    check_prerequisites
    clean_env_file
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