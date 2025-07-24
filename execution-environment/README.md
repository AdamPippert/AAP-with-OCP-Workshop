# Execution Environment for AAP Workshop

This directory contains the configuration files for building a custom execution environment for the Advanced Ansible Automation Platform (AAP) 2.5 Workshop.

## Overview

The execution environment provides a containerized runtime environment that includes all necessary dependencies for the workshop exercises, including:

- Ansible collections for Kubernetes and OpenShift integration
- System packages for OpenShift CLI tools
- Python dependencies for cloud and container operations
- Workshop-specific configuration and tooling

## Files

- `execution-environment.yml` - Main configuration file for ansible-builder
- `requirements.yml` - Ansible collections required for the workshop
- `requirements.txt` - Python packages needed by the collections
- `bindep.txt` - System packages required for the execution environment

## Quick Start Options

### Option 1: Use Published Image (Recommended for Attendees)

The workshop provides a pre-built execution environment to save time:

```bash
# Set environment variable to use published image
export USE_PUBLISHED_EE=true

# Run workshop setup (will automatically pull published image)
./scripts/exercise0/setup_workshop.sh
```

The published image is available at: `quay.io/aap-workshop/aap-workshop-ee:latest`

### Option 2: Build Locally

If you prefer to build the execution environment yourself:

```bash
# Disable published EE usage (default)
export USE_PUBLISHED_EE=false

# Run workshop setup (will build locally)
./scripts/exercise0/setup_workshop.sh
```

Or build manually:

```bash
# From the repository root
./scripts/build_execution_environment.sh

# Or with custom options
./scripts/build_execution_environment.sh -t workshop-v1.0 -r quay.io/myorg -p
```

## Prerequisites for Local Building

- `ansible-builder` installed (`pip install ansible-builder`)
- Docker or Podman container runtime
- Access to `registry.redhat.io` for the base UBI image

## Publishing for Workshop Distribution

Workshop instructors can publish the execution environment to a public registry:

```bash
# Build and publish to default registry (quay.io/aap-workshop)
./scripts/publish_execution_environment.sh --push

# Custom registry and namespace
./scripts/publish_execution_environment.sh \
    -r docker.io \
    -n myorganization \
    -t v1.0 \
    --latest \
    --push
```

This creates:
- Published container image
- Workshop configuration file (`published-ee-config.env`)
- Documentation (`docs/published-execution-environment.md`)

## Included Collections

| Collection | Version | Purpose |
|------------|---------|---------|
| `kubernetes.core` | >=3.0.0 | Core Kubernetes operations |
| `redhat.openshift` | >=2.0.0 | OpenShift-specific modules |
| `community.general` | >=7.0.0 | General utility modules |
| `community.crypto` | >=2.0.0 | Certificate management |
| `ansible.posix` | >=1.0.0 | POSIX system operations |
| `community.docker` | >=3.0.0 | Container operations |
| `community.okd` | >=2.0.0 | Additional OpenShift utilities |
| `ansible.utils` | >=2.0.0 | Network and data processing |
| `community.kubernetes` | >=2.0.0 | Additional K8s utilities |

## Usage in AAP Controller

The workshop setup automatically creates the execution environment in AAP Controller. Manual configuration:

1. Log into AAP Controller web interface
2. Navigate to **Administration** > **Execution Environments**
3. Click **Add** to create a new execution environment
4. Configure:
   - **Name**: Workshop-EE-{GUID}
   - **Image**: Published image or local build
   - **Organization**: Default
   - **Pull**: Always (for registry images) or Missing (for local builds)

## Integration with Workshop

### Automatic Setup

The execution environment is automatically configured during Exercise 0:

1. **Check**: Determines whether to use published or build locally
2. **Acquire**: Pulls published image or builds from source
3. **Validate**: Tests collections and CLI tools availability
4. **Register**: Creates execution environment in AAP Controller
5. **Associate**: Links to job templates for workshop exercises

### Environment Variables

- `USE_PUBLISHED_EE=true/false` - Use published vs local build
- `PUBLISHED_EE_IMAGE` - Override default published image
- `SKIP_EE_BUILD=true` - Skip building (use existing local image)

### Registry Integration

The setup script can push to OpenShift's internal registry:

```bash
# Automatic registry detection and push
./scripts/exercise0/setup_workshop.sh
```

Images are pushed to: `default-route-openshift-image-registry.{cluster-domain}/workshop-aap/aap-workshop-ee:{guid}`

## Testing the Execution Environment

```bash
# Test collections are installed
podman run --rm aap-workshop-ee:latest ansible-galaxy collection list

# Test OpenShift CLI is available
podman run --rm aap-workshop-ee:latest oc version --client

# Test published image
podman run --rm quay.io/aap-workshop/aap-workshop-ee:latest ansible-galaxy collection list kubernetes.core

# Interactive testing
podman run --rm -it aap-workshop-ee:latest /bin/bash
```

## Troubleshooting

### Published Image Issues

1. **Pull failures**: Check internet connectivity and registry access
2. **Authentication errors**: Ensure registry is public or credentials are configured
3. **Image not found**: Verify the published image name and tag

### Build Failures

1. **Base image pull errors**: Ensure you have access to `registry.redhat.io`
2. **Collection install failures**: Check internet connectivity and collection versions
3. **System package errors**: Verify `bindep.txt` contains valid package names

### Runtime Issues

1. **Collection not found**: Verify the collection is listed in `requirements.yml`
2. **Binary not available**: Check that required tools are installed via `bindep.txt`
3. **Permission errors**: Ensure the execution environment runs with appropriate user permissions

### AAP Controller Integration

1. **EE not visible**: Check organization assignment and user permissions
2. **Job failures**: Verify the image is accessible from AAP nodes
3. **Collection errors**: Ensure all required collections are installed in the EE

## Customization

To add additional collections or tools:

1. Add collections to `requirements.yml`
2. Add Python packages to `requirements.txt`
3. Add system packages to `bindep.txt`
4. Modify `execution-environment.yml` for advanced configuration
5. Rebuild and republish the execution environment

## Workshop Flow

1. **Pre-workshop**: Instructor publishes execution environment to public registry
2. **Setup**: Attendees run setup script with `USE_PUBLISHED_EE=true`
3. **Exercises**: Job templates automatically use the configured execution environment
4. **Advanced**: Attendees can build custom EEs for additional exercises