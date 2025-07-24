# Exercise 0: Workshop Environment Setup

## Overview

Exercise 0 prepares the workshop environment by parsing credentials from `details.txt` and configuring the OpenShift cluster and Automation Controller for the subsequent workshop modules.

## Prerequisites

- OpenShift CLI (`oc`) installed and available in PATH
- Ansible installed with `kubernetes.core` collection
- Access to OpenShift cluster with cluster-admin privileges
- `details.txt` file populated by workshop moderator

## Setup Process

### 1. Environment Configuration

```bash
./scripts/exercise0/setup_workshop.sh
```

This script:
- Parses `details.txt` for credentials and URLs
- Creates `.env` file with environment variables
- Verifies OpenShift and AAP connectivity
- Creates initial workshop namespace

### 2. Infrastructure Setup

```bash
ansible-playbook playbooks/exercise0/setup.yml
```

This playbook creates:
- Workshop namespaces (`workshop-aap`, `workshop-aap-dev`, `workshop-aap-test`, `workshop-aap-prod`)
- Service account with cluster-admin permissions
- Resource quotas for each environment
- Network policies for environment isolation
- Workshop configuration ConfigMap

### 3. Environment Validation

```bash
./scripts/exercise0/validate_setup.sh
```

This script validates:
- OpenShift connectivity and authentication
- Namespace creation and configuration
- Service account and RBAC setup
- Resource quotas and network policies
- Automation Controller accessibility

## Environment Details

### Namespaces Created

| Namespace | Purpose | CPU Limit | Memory Limit |
|-----------|---------|-----------|--------------|
| `workshop-aap` | Main workshop namespace | 32 CPU | 64Gi |
| `workshop-aap-dev` | Development environment | 8 CPU | 16Gi |
| `workshop-aap-test` | Test environment | 16 CPU | 32Gi |
| `workshop-aap-prod` | Production environment | 32 CPU | 64Gi |

### Service Account

- **Name**: `workshop-automation`
- **Namespace**: `workshop-aap`
- **Permissions**: Cluster-admin via `workshop-automation-role` ClusterRole

### Security

- Network policies isolate each environment namespace
- Resource quotas prevent resource exhaustion
- Service account follows least-privilege principles for workshop activities

## Troubleshooting

### Common Issues

1. **OpenShift Login Required**
   ```bash
   oc login <cluster-url>
   ```

2. **Missing Ansible Collections**
   ```bash
   ansible-galaxy collection install kubernetes.core
   ```

3. **Permission Denied**
   - Ensure your OpenShift user has cluster-admin privileges
   - Check if service account tokens are properly configured

4. **Network Connectivity**
   - Verify AAP URL accessibility
   - Check firewall rules for OpenShift API access

### Re-running Setup

If setup fails, clean up and retry:

```bash
# Clean up resources
oc delete namespace workshop-aap workshop-aap-dev workshop-aap-test workshop-aap-prod
oc delete clusterrolebinding workshop-automation-binding
oc delete clusterrole workshop-automation-role

# Re-run setup
./scripts/exercise0/setup_workshop.sh
ansible-playbook playbooks/exercise0/setup.yml
./scripts/exercise0/validate_setup.sh
```

## Next Steps

After successful validation, proceed to:
- **Module 1**: Dynamic Inventory and AAP Integration
- Run: `ansible-playbook playbooks/module1/exercise1-1-test-inventory.yml`