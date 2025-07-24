#!/bin/bash

# Publish Execution Environment Script
# Builds and publishes the execution environment to a public registry
# for workshop attendees to use without building their own

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EE_DIR="${REPO_ROOT}/execution-environment"

# Default configuration
DEFAULT_REGISTRY="quay.io"
DEFAULT_NAMESPACE="aap-workshop"
DEFAULT_IMAGE_NAME="aap-workshop-ee"
DEFAULT_TAG="latest"

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
AAP Workshop Execution Environment Publisher

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -r, --registry REG      Registry to publish to (default: ${DEFAULT_REGISTRY})
    -n, --namespace NS      Registry namespace (default: ${DEFAULT_NAMESPACE})
    -i, --image IMAGE       Image name (default: ${DEFAULT_IMAGE_NAME})
    -t, --tag TAG           Image tag (default: ${DEFAULT_TAG})
    --platforms PLATFORMS   Target platforms (default: linux/amd64,linux/arm64)
    --push                  Push to registry (default: build only)
    --latest                Also tag as 'latest'
    -h, --help              Show this help

EXAMPLES:
    $0                                          # Build locally only
    $0 --push                                   # Build and push to quay.io
    $0 -r docker.io -n myorg --push           # Push to Docker Hub
    $0 -t v1.0 --latest --push                # Tag as v1.0 and latest

DESCRIPTION:
    This script builds and optionally publishes the AAP Workshop execution
    environment to a public registry. This allows workshop attendees to use
    a pre-built execution environment without having to build their own.

    The execution environment includes:
    - kubernetes.core collection (>=3.0.0)
    - redhat.openshift collection (>=2.0.0)
    - OpenShift CLI tools (oc, kubectl)
    - Additional collections for workshop exercises
    - Workshop-specific configuration

PREREQUISITES:
    - ansible-builder installed (pip install ansible-builder)
    - Docker or Podman with buildx/buildah support
    - Registry credentials configured (docker/podman login)
    - Access to registry.redhat.io (for base image)

EOF
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check for ansible-builder
    if ! command -v ansible-builder &> /dev/null; then
        error "ansible-builder not found. Install with: pip install ansible-builder"
        exit 1
    fi
    
    # Check for container runtime
    if command -v podman &> /dev/null; then
        CONTAINER_RUNTIME="podman"
    elif command -v docker &> /dev/null; then
        CONTAINER_RUNTIME="docker"
    else
        error "Neither podman nor docker found. Please install a container runtime."
        exit 1
    fi
    
    # Check for buildx/buildah for multi-platform builds
    if [[ "${CONTAINER_RUNTIME}" == "docker" ]]; then
        if ! docker buildx version &> /dev/null; then
            warning "Docker buildx not available, multi-platform builds may not work"
        fi
    fi
    
    # Check execution environment directory
    if [[ ! -d "${EE_DIR}" ]]; then
        error "Execution environment directory not found: ${EE_DIR}"
        exit 1
    fi
    
    # Check required files
    local required_files=("execution-environment.yml" "requirements.yml" "requirements.txt" "bindep.txt")
    for file in "${required_files[@]}"; do
        if [[ ! -f "${EE_DIR}/${file}" ]]; then
            error "Required file not found: ${EE_DIR}/${file}"
            exit 1
        fi
    done
    
    success "Prerequisites check passed (using ${CONTAINER_RUNTIME})"
}

build_execution_environment() {
    local registry="$1"
    local namespace="$2"
    local image_name="$3"
    local tag="$4"
    local platforms="$5"
    local full_name="${registry}/${namespace}/${image_name}:${tag}"
    
    log "Building execution environment: ${full_name}"
    log "Target platforms: ${platforms}"
    
    # Change to EE directory
    cd "${EE_DIR}"
    
    # Build arguments for ansible-builder
    local build_args=(
        --tag "${full_name}"
        --container-runtime "${CONTAINER_RUNTIME}"
    )
    
    # Add platform support if using docker buildx
    if [[ "${CONTAINER_RUNTIME}" == "docker" ]] && docker buildx version &> /dev/null; then
        build_args+=(--build-outputs-dir /tmp/build-outputs)
    fi
    
    # Build the execution environment
    log "Running ansible-builder build..."
    if ansible-builder build "${build_args[@]}" .; then
        success "Successfully built execution environment: ${full_name}"
        
        # Show image details
        log "Image details:"
        ${CONTAINER_RUNTIME} images "${full_name}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" || true
        
        return 0
    else
        error "Failed to build execution environment"
        return 1
    fi
}

tag_as_latest() {
    local registry="$1"
    local namespace="$2"
    local image_name="$3"
    local tag="$4"
    local source_name="${registry}/${namespace}/${image_name}:${tag}"
    local latest_name="${registry}/${namespace}/${image_name}:latest"
    
    if [[ "${tag}" != "latest" ]]; then
        log "Tagging as latest: ${latest_name}"
        if ${CONTAINER_RUNTIME} tag "${source_name}" "${latest_name}"; then
            success "Tagged as latest: ${latest_name}"
            return 0
        else
            error "Failed to tag as latest"
            return 1
        fi
    fi
}

push_to_registry() {
    local registry="$1"
    local namespace="$2"
    local image_name="$3"
    local tag="$4"
    local tag_latest="$5"
    local full_name="${registry}/${namespace}/${image_name}:${tag}"
    
    log "Pushing to registry: ${full_name}"
    
    # Check if logged into registry
    if ! ${CONTAINER_RUNTIME} info 2>/dev/null | grep -q "${registry}" 2>/dev/null; then
        warning "Not logged into ${registry}. Attempting to push anyway..."
    fi
    
    # Push main tag
    if ${CONTAINER_RUNTIME} push "${full_name}"; then
        success "Successfully pushed: ${full_name}"
    else
        error "Failed to push: ${full_name}"
        return 1
    fi
    
    # Push latest tag if requested
    if [[ "${tag_latest}" == "true" && "${tag}" != "latest" ]]; then
        local latest_name="${registry}/${namespace}/${image_name}:latest"
        log "Pushing latest tag: ${latest_name}"
        if ${CONTAINER_RUNTIME} push "${latest_name}"; then
            success "Successfully pushed: ${latest_name}"
        else
            error "Failed to push latest tag"
            return 1
        fi
    fi
    
    return 0
}

generate_workshop_config() {
    local registry="$1"
    local namespace="$2"
    local image_name="$3"
    local tag="$4"
    local full_name="${registry}/${namespace}/${image_name}:${tag}"
    
    log "Generating workshop configuration..."
    
    # Update the setup script with the published image
    local config_file="${REPO_ROOT}/published-ee-config.env"
    cat > "${config_file}" << EOF
# Published Execution Environment Configuration
# Generated on $(date)
# Use this configuration to skip building EE during workshop setup

# Published execution environment image
PUBLISHED_EE_IMAGE=${full_name}
PUBLISHED_EE_REGISTRY=${registry}
PUBLISHED_EE_NAMESPACE=${namespace}
PUBLISHED_EE_NAME=${image_name}
PUBLISHED_EE_TAG=${tag}

# Workshop setup options
SKIP_EE_BUILD=true
USE_PUBLISHED_EE=true

# Registry information
REGISTRY_PUBLIC=true
REGISTRY_AUTH_REQUIRED=false
EOF
    
    success "Configuration written to: ${config_file}"
    
    # Create documentation
    local doc_file="${REPO_ROOT}/docs/published-execution-environment.md"
    cat > "${doc_file}" << EOF
# Published Execution Environment

This document describes the pre-built execution environment available for the AAP Workshop.

## Image Details

- **Registry**: ${registry}
- **Image**: ${full_name}
- **Base**: Red Hat UBI 8
- **Size**: $(${CONTAINER_RUNTIME} images --format "{{.Size}}" "${full_name}" 2>/dev/null || "Unknown")

## Included Collections

- kubernetes.core (>=3.0.0)
- redhat.openshift (>=2.0.0)
- community.general (>=7.0.0)
- community.crypto (>=2.0.0)
- ansible.posix (>=1.0.0)
- community.docker (>=3.0.0)
- community.okd (>=2.0.0)
- ansible.utils (>=2.0.0)
- community.kubernetes (>=2.0.0)

## Included Tools

- OpenShift CLI (oc)
- Kubernetes CLI (kubectl)
- Workshop-specific configuration

## Usage in Workshop

To use this pre-built execution environment:

1. Set environment variable: \`export USE_PUBLISHED_EE=true\`
2. Run setup script: \`./scripts/exercise0/setup_workshop.sh\`
3. The script will automatically use the published image

## Manual Usage

\`\`\`bash
# Pull the image
${CONTAINER_RUNTIME} pull ${full_name}

# Test collections
${CONTAINER_RUNTIME} run --rm ${full_name} ansible-galaxy collection list

# Test OpenShift CLI
${CONTAINER_RUNTIME} run --rm ${full_name} oc version --client
\`\`\`

## Building Locally

If you prefer to build locally instead of using the published image:

\`\`\`bash
# Disable published EE usage
export USE_PUBLISHED_EE=false

# Run setup (will build locally)
./scripts/exercise0/setup_workshop.sh
\`\`\`

---
Generated on $(date)
EOF
    
    success "Documentation written to: ${doc_file}"
}

show_summary() {
    local registry="$1"
    local namespace="$2"
    local image_name="$3"
    local tag="$4"
    local pushed="$5"
    local full_name="${registry}/${namespace}/${image_name}:${tag}"
    
    echo
    echo "=================================="
    echo "  EXECUTION ENVIRONMENT READY"
    echo "=================================="
    echo
    echo "Image: ${full_name}"
    
    if [[ "${pushed}" == "true" ]]; then
        echo "Status: Published to registry"
        echo
        echo "Workshop attendees can now use:"
        echo "  export USE_PUBLISHED_EE=true"
        echo "  ./scripts/exercise0/setup_workshop.sh"
    else
        echo "Status: Built locally only"
        echo
        echo "To publish to registry:"
        echo "  $0 --push"
    fi
    
    echo
    echo "Testing commands:"
    echo "  ${CONTAINER_RUNTIME} pull ${full_name}"
    echo "  ${CONTAINER_RUNTIME} run --rm ${full_name} ansible-galaxy collection list"
    echo "  ${CONTAINER_RUNTIME} run --rm ${full_name} oc version --client"
    echo
}

main() {
    local registry="${DEFAULT_REGISTRY}"
    local namespace="${DEFAULT_NAMESPACE}"
    local image_name="${DEFAULT_IMAGE_NAME}"
    local tag="${DEFAULT_TAG}"
    local platforms="linux/amd64,linux/arm64"
    local push_image="false"
    local tag_latest="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--registry)
                registry="$2"
                shift 2
                ;;
            -n|--namespace)
                namespace="$2"
                shift 2
                ;;
            -i|--image)
                image_name="$2"
                shift 2
                ;;
            -t|--tag)
                tag="$2"
                shift 2
                ;;
            --platforms)
                platforms="$2"
                shift 2
                ;;
            --push)
                push_image="true"
                shift
                ;;
            --latest)
                tag_latest="true"
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
    
    # Check prerequisites
    check_prerequisites
    
    # Build execution environment
    if ! build_execution_environment "${registry}" "${namespace}" "${image_name}" "${tag}" "${platforms}"; then
        exit 1
    fi
    
    # Tag as latest if requested
    if [[ "${tag_latest}" == "true" ]]; then
        tag_as_latest "${registry}" "${namespace}" "${image_name}" "${tag}"
    fi
    
    # Push to registry if requested
    if [[ "${push_image}" == "true" ]]; then
        if ! push_to_registry "${registry}" "${namespace}" "${image_name}" "${tag}" "${tag_latest}"; then
            exit 1
        fi
        
        # Generate workshop configuration
        generate_workshop_config "${registry}" "${namespace}" "${image_name}" "${tag}"
    fi
    
    # Show summary
    show_summary "${registry}" "${namespace}" "${image_name}" "${tag}" "${push_image}"
}

main "$@"