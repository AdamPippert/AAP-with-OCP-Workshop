# AAP Workshop Execution Environment

This directory contains the definition files for building a custom Execution Environment (EE) for the Advanced AAP 2.5 with OpenShift workshop.

## Files Overview

- **`execution-environment.yml`** - Main build configuration for ansible-builder
- **`requirements.yml`** - Ansible collections to install
- **`requirements.txt`** - Python packages to install  
- **`bindep.txt`** - System packages to install

## Building the Execution Environment

### Prerequisites

- `ansible-builder` installed (`pip install ansible-builder`)
- Docker or Podman available
- Access to registry.redhat.io (for base image)

### Build Commands

```bash
# Build the execution environment
cd execution-environment/
ansible-builder build -t aap-workshop-ee:latest .

# Tag for registry
docker tag aap-workshop-ee:latest <your-registry>/aap-workshop-ee:latest

# Push to registry
docker push <your-registry>/aap-workshop-ee:latest
```

## Included Collections

- **kubernetes.core** - Core Kubernetes/OpenShift modules
- **redhat.openshift** - Red Hat OpenShift specific modules
- **community.general** - General purpose community modules
- **community.crypto** - Cryptography and certificate modules
- **ansible.posix** - POSIX system modules
- **community.docker** - Docker container modules
- **community.okd** - OpenShift community modules
- **ansible.utils** - Network and data processing utilities
- **community.kubernetes** - Additional Kubernetes utilities

## Included Tools

- OpenShift CLI (`oc`)
- Kubernetes CLI (`kubectl`) 
- Standard Linux utilities (`jq`, `curl`, `wget`, etc.)
- Python libraries for Kubernetes/OpenShift integration

## Workshop Integration

This execution environment is automatically:
1. Built during workshop setup (if needed)
2. Pushed to AAP Controller
3. Associated with all workshop job templates
4. Used for all workshop exercise execution

## Customization

To add additional collections or packages:

1. Edit `requirements.yml` for Ansible collections
2. Edit `requirements.txt` for Python packages
3. Edit `bindep.txt` for system packages
4. Rebuild the execution environment

## Troubleshooting

### Build Issues

- Ensure base image access: `docker login registry.redhat.io`
- Check ansible-builder version: `ansible-builder --version`
- Verify file permissions in execution-environment directory

### Runtime Issues

- Check collection availability: `ansible-galaxy collection list`
- Verify Python packages: `pip list`
- Test OpenShift CLI: `oc version`

## Security Considerations

- Base image uses Red Hat UBI8 for security and compliance
- All packages use pinned versions for reproducibility
- Workshop user has limited privileges
- Image includes latest security updates