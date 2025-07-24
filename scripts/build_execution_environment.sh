#!/bin/bash

# Execution Environment Build Script
# Builds the custom execution environment for the AAP Workshop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EE_DIR="${REPO_ROOT}/execution-environment"
DEFAULT_TAG="latest"
DEFAULT_NAME="aap-workshop-ee"

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
AAP Workshop Execution Environment Builder

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -n, --name NAME     Image name (default: ${DEFAULT_NAME})
    -t, --tag TAG       Image tag (default: ${DEFAULT_TAG})
    -r, --registry REG  Registry to push to (optional)
    -p, --push          Push to registry after build
    --force             Force rebuild even if image exists
    -h, --help          Show this help

EXAMPLES:
    $0                                          # Build with defaults
    $0 -t workshop-v1.0                       # Custom tag
    $0 -r quay.io/myorg -p                    # Build and push to registry
    $0 -n custom-ee -t latest --force         # Force rebuild with custom name

DESCRIPTION:
    This script builds a custom execution environment for the AAP Workshop
    using ansible-builder. The execution environment includes:
    
    - kubernetes.core collection
    - redhat.openshift collection  
    - OpenShift CLI tools (oc, kubectl)
    - Python dependencies for K8s integration
    - Additional workshop-specific collections

PREREQUISITES:
    - ansible-builder installed (pip install ansible-builder)
    - Docker or Podman available
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
    local image_name="$1"
    local image_tag="$2"
    local force_build="$3"
    local full_name="${image_name}:${image_tag}"
    
    log "Building execution environment: ${full_name}"
    
    # Check if image already exists (unless force rebuild)
    if [[ "${force_build}" == "false" ]] && ${CONTAINER_RUNTIME} images -q "${full_name}" &> /dev/null; then
        warning "Image ${full_name} already exists. Use --force to rebuild."
        return 0
    fi
    
    # Change to EE directory
    cd "${EE_DIR}"
    
    # Build the execution environment
    log "Running ansible-builder build..."
    if ansible-builder build -t "${full_name}" . --container-runtime "${CONTAINER_RUNTIME}"; then
        success "Successfully built execution environment: ${full_name}"
        
        # Show image details
        log "Image details:"
        ${CONTAINER_RUNTIME} images "${full_name}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
        
        return 0
    else
        error "Failed to build execution environment"
        return 1
    fi
}

push_to_registry() {
    local image_name="$1"
    local image_tag="$2"
    local registry="$3"
    local source_name="${image_name}:${image_tag}"
    local target_name="${registry}/${image_name}:${image_tag}"
    
    log "Pushing to registry: ${target_name}"
    
    # Tag for registry
    if ${CONTAINER_RUNTIME} tag "${source_name}" "${target_name}"; then
        log "Tagged image: ${target_name}"
    else
        error "Failed to tag image for registry"
        return 1
    fi
    
    # Push to registry
    if ${CONTAINER_RUNTIME} push "${target_name}"; then
        success "Successfully pushed to registry: ${target_name}"
        return 0
    else
        error "Failed to push to registry"
        return 1
    fi
}

show_build_summary() {
    local image_name="$1"
    local image_tag="$2"
    local registry="${3:-}"
    local full_name="${image_name}:${image_tag}"
    
    echo
    echo "=================================="
    echo "  BUILD COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo
    echo "Built Image: ${full_name}"
    
    if [[ -n "${registry}" ]]; then
        echo "Registry: ${registry}/${full_name}"
    fi
    
    echo
    echo "Usage in AAP:"
    echo "  1. Log into AAP Controller"
    echo "  2. Navigate to Administration > Execution Environments"
    echo "  3. Create new execution environment with image: ${full_name}"
    echo "  4. Associate with job templates"
    echo
    echo "Testing:"
    echo "  ${CONTAINER_RUNTIME} run --rm -it ${full_name} ansible-galaxy collection list"
    echo "  ${CONTAINER_RUNTIME} run --rm -it ${full_name} oc version"
    echo
}

main() {
    local image_name="${DEFAULT_NAME}"
    local image_tag="${DEFAULT_TAG}"
    local registry=""
    local push_image="false"
    local force_build="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                image_name="$2"
                shift 2
                ;;
            -t|--tag)
                image_tag="$2"
                shift 2
                ;;
            -r|--registry)
                registry="$2"
                shift 2
                ;;
            -p|--push)
                push_image="true"
                shift
                ;;
            --force)
                force_build="true"
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
    
    # Validate registry requirement for pushing
    if [[ "${push_image}" == "true" && -z "${registry}" ]]; then
        error "Registry must be specified when using --push"
        exit 1
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Build execution environment
    if ! build_execution_environment "${image_name}" "${image_tag}" "${force_build}"; then
        exit 1
    fi
    
    # Push to registry if requested
    if [[ "${push_image}" == "true" ]]; then
        if ! push_to_registry "${image_name}" "${image_tag}" "${registry}"; then
            exit 1
        fi
    fi
    
    # Show summary
    show_build_summary "${image_name}" "${image_tag}" "${registry}"
}

main "$@"