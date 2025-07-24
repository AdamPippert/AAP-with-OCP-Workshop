# Troubleshooting Guide

This document provides solutions to common issues encountered during the AAP Workshop setup.

## Execution Environment Build Issues

### TypeError: '>' not supported between instances of 'str' and 'int'

This error occurs during execution environment building with ansible-builder and is typically caused by version comparison issues in dependency resolution.

**Quick Fix:**
```bash
# Use the published execution environment instead of building locally
export USE_PUBLISHED_EE=true
./scripts/exercise0/setup_workshop.sh
```

**Alternative Solutions:**

1. **Upgrade ansible-builder:**
```bash
pip install --upgrade ansible-builder
./scripts/exercise0/setup_workshop.sh
```

2. **Use Python virtual environment:**
```bash
python -m venv ee-build-env
source ee-build-env/bin/activate
pip install ansible-builder
./scripts/exercise0/setup_workshop.sh
```

3. **Use the dedicated build script:**
```bash
# This uses the build script which has better error handling
./scripts/build_execution_environment.sh -t workshop-ee
```

4. **Manual collection installation debugging:**
```bash
cd execution-environment/
# Test collection installation manually
ansible-galaxy collection install -r requirements.yml --force
```

### Registry Access Issues

**Red Hat Registry Authentication:**
```bash
# Login to Red Hat registry
podman login registry.redhat.io
# or
docker login registry.redhat.io
```

**OpenShift Internal Registry Issues:**
```bash
# Check OpenShift registry route
oc get route -n openshift-image-registry

# Login to OpenShift registry
oc registry login
```

### Container Runtime Issues

**Podman vs Docker:**
```bash
# Check which runtime is being used
podman --version || docker --version

# Force specific runtime
export CONTAINER_RUNTIME=podman
# or
export CONTAINER_RUNTIME=docker
```

## AAP Controller Setup Issues

### API Connection Failures

**Check AAP URL and credentials:**
```bash
# Test basic connectivity
curl -k -s "${AAP_URL}/api/v2/ping/"

# Check environment variables
cat .env | grep AAP
```

**Authentication Issues:**
```bash
# Test authentication
curl -k -H "Authorization: Bearer ${AAP_TOKEN}" "${AAP_URL}/api/controller/v2/me/"
```

### Job Template Creation Issues

**Missing Execution Environment:**
```bash
# Check if EE was created in AAP
curl -k -H "Authorization: Bearer ${AAP_TOKEN}" "${AAP_URL}/api/controller/v2/execution_environments/"
```

**Project Sync Issues:**
```bash
# Check project status in AAP Controller
# Navigate to Resources > Projects and check sync status
```

## OpenShift Connection Issues

### Bearer Token Authentication

**Token Expired:**
```bash
# Get new token from OpenShift console
# Copy from: Copy Login Command > Display Token

# Update .env file with new token
sed -i 's/OCP_BEARER_TOKEN=.*/OCP_BEARER_TOKEN=new_token_here/' .env
```

**Manual Login:**
```bash
oc login --token=<your-token> --server=<api-server-url>
```

### Namespace Issues

**Permission Denied:**
```bash
# Check current user permissions
oc auth can-i create namespaces

# Check if namespace exists
oc get namespace workshop-aap
```

## Environment Variable Issues

### Missing Configuration

**Check .env file:**
```bash
# Verify all required variables are set
cat .env

# Expected variables:
# - AAP_URL, AAP_USERNAME, AAP_PASSWORD, AAP_TOKEN
# - OCP_API_URL, OCP_BEARER_TOKEN, OCP_CLUSTER_DOMAIN
# - WORKSHOP_GUID
```

**Recreate .env file:**
```bash
# Remove existing .env and regenerate
rm -f .env
./scripts/exercise0/setup_workshop.sh
```

## Network Connectivity Issues

### Firewall/Proxy Issues

**Corporate Network:**
```bash
# Set proxy variables if needed
export HTTP_PROXY=http://proxy.company.com:8080
export HTTPS_PROXY=http://proxy.company.com:8080
export NO_PROXY=localhost,127.0.0.1,.local

# Test connectivity
curl -k -s google.com
```

### DNS Resolution

**Check cluster domain resolution:**
```bash
# Test cluster domain resolution
nslookup ${OCP_CLUSTER_DOMAIN}

# Test AAP URL resolution
nslookup $(echo ${AAP_URL} | sed 's|https\?://||' | cut -d/ -f1)
```

## Quick Recovery Commands

### Complete Reset

```bash
# Clean up and start over
rm -f .env
oc delete namespace workshop-aap --ignore-not-found=true
podman rmi -f aap-workshop-ee:* --ignore-errors
./scripts/exercise0/setup_workshop.sh
```

### Use Published EE Only

```bash
# Skip all building, use published execution environment
export USE_PUBLISHED_EE=true
export SKIP_EE_BUILD=true
./scripts/exercise0/setup_workshop.sh
```

### Debug Mode

```bash
# Run with verbose logging
bash -x ./scripts/exercise0/setup_workshop.sh
```

## Getting Help

### Log Files

Build logs are saved to `/tmp/ee-build-*.log` when builds fail.

### Environment Information

```bash
# Gather environment info for support
echo "=== System Info ==="
uname -a
echo "=== Container Runtime ==="
podman --version 2>/dev/null || docker --version 2>/dev/null || echo "None found"
echo "=== Ansible Builder ==="
ansible-builder --version 2>/dev/null || echo "Not installed"
echo "=== OpenShift CLI ==="
oc version --client 2>/dev/null || echo "Not installed"
echo "=== Environment Variables ==="
cat .env 2>/dev/null || echo "No .env file found"
```

### Workshop Support

For workshop-specific issues:
1. Check this troubleshooting guide first
2. Review the build logs in `/tmp/ee-build-*.log`
3. Try the published execution environment option
4. Contact workshop instructor with specific error messages