# Module 1: Dynamic Inventory and AAP Integration - Workshop Guide

## Overview

**Duration:** 40 minutes  
**Objective:** Master advanced inventory management patterns for multi-cluster OpenShift environments

In this module, you'll progress from basic single-cluster inventory discovery to advanced event-driven inventory synchronization, building the foundation for all subsequent workshop activities.

## Prerequisites

Before starting this module, ensure you have:

- [ ] OpenShift cluster access with valid kubeconfig
- [ ] Ansible Automation Platform 2.5 access
- [ ] `kubernetes.core` collection installed (`ansible-galaxy collection install kubernetes.core`)
- [ ] Basic understanding of Ansible inventory concepts
- [ ] `kubectl` or `oc` CLI tools configured

### Quick Environment Check

```bash
# Verify cluster connectivity
kubectl get nodes

# Check your current context
kubectl config current-context

# Verify Ansible collections
ansible-galaxy collection list | grep kubernetes.core

# Test basic OpenShift API access
kubectl get pods --all-namespaces | head -5
```

## Module Structure

| Exercise | Duration | Focus Area |
|----------|----------|------------|
| 1.1 | 10 min | Single-Cluster Dynamic Inventory |
| 1.2 | 15 min | Multi-Cluster Inventory Configuration |
| 1.3 | 10 min | Event-Driven Inventory Updates |
| 1.4 | 5 min | Troubleshooting and Optimization |

---

## Exercise 1.1: Single-Cluster Dynamic Inventory

**⏱️ Time Allocation:** 10 minutes (5 min hands-on, 5 min validation)

### Learning Objectives
- Configure basic OpenShift service discovery using `kubernetes.core.k8s`
- Implement namespace-based and application-based grouping
- Test inventory discovery and validate results

### Step-by-Step Instructions

#### Step 1: Review the Inventory Configuration (2 minutes)

```bash
# Examine the single-cluster inventory file
cat inventory/exercise1-1-single-cluster.yml
```

**Key Configuration Points:**
- `plugin: kubernetes.core.k8s` - Uses the Kubernetes dynamic inventory plugin
- `connections` - Defines which cluster context to use
- `compose` - Creates host variables from pod metadata
- `keyed_groups` - Creates dynamic groups based on pod properties
- `filters` - Excludes system pods and non-running pods

#### Step 2: Test the Inventory Configuration (3 minutes)

```bash
# Run the validation playbook
ansible-playbook playbooks/module1/exercise1-1-test-inventory.yml

# Manually test inventory discovery
ansible-inventory -i inventory/exercise1-1-single-cluster.yml --list

# View inventory structure
ansible-inventory -i inventory/exercise1-1-single-cluster.yml --graph
```

#### Step 3: Validation Checkpoint (5 minutes)

**Expected Results:**
- ✅ Playbook completes successfully
- ✅ Test pods are created and discovered
- ✅ Dynamic groups are created (namespace_*, app_*, node_*)
- ✅ Pod IPs are properly assigned as ansible_host values

**Troubleshooting Common Issues:**

| Issue | Symptoms | Solution |
|-------|----------|----------|
| No pods discovered | Empty inventory output | Check cluster connectivity: `kubectl get pods` |
| Permission denied | 403 Forbidden errors | Verify RBAC: `kubectl auth can-i get pods` |
| Wrong context | Connection refused | Check context: `kubectl config current-context` |

---

## Exercise 1.2: Multi-Cluster Inventory Configuration  

**⏱️ Time Allocation:** 15 minutes (10 min configuration, 5 min testing)

### Learning Objectives
- Configure inventory for multiple OpenShift clusters
- Implement cross-cluster resource discovery
- Create environment-specific grouping strategies

### Step-by-Step Instructions

#### Step 1: Update Cluster Contexts (3 minutes)

```bash
# Check available contexts
kubectl config get-contexts

# Update inventory file with your actual context names
# Edit inventory/exercise1-2-multi-cluster.yml
# Replace cluster-dev, cluster-test, cluster-prod with your contexts
```

**🔧 Configuration Note:** If you only have one cluster, you can simulate multiple clusters by creating multiple namespaces (e.g., `ims-dev`, `ims-test`, `ims-prod`) and using the same context for all connections.

#### Step 2: Run Multi-Cluster Discovery (7 minutes)

```bash
# Execute the multi-cluster test playbook
ansible-playbook playbooks/module1/exercise1-2-test-multi-cluster.yml

# Examine the multi-cluster inventory structure
ansible-inventory -i inventory/exercise1-2-multi-cluster.yml --graph

# View full inventory data
ansible-inventory -i inventory/exercise1-2-multi-cluster.yml --list | jq
```

#### Step 3: Analyze Cross-Cluster Grouping (5 minutes)

**Expected Group Types:**
- `cluster_*` - Groups pods by cluster context
- `env_*` - Groups pods by environment (development/testing/production)
- `app_cluster_*` - Application-specific groups per cluster
- `ns_cluster_*` - Namespace groups with cluster identification

```bash
# Filter for cluster-specific groups
ansible-inventory -i inventory/exercise1-2-multi-cluster.yml --list | jq 'keys[]' | grep cluster_

# View environment-based groups
ansible-inventory -i inventory/exercise1-2-multi-cluster.yml --list | jq 'keys[]' | grep env_
```

---

## Exercise 1.3: Event-Driven Inventory Updates

**⏱️ Time Allocation:** 10 minutes (5 min setup, 5 min testing)

### Learning Objectives
- Understand webhook-based inventory synchronization concepts
- Configure automated inventory refresh triggers
- Implement error handling for webhook failures

### Step-by-Step Instructions

#### Step 1: Review Webhook Configuration (2 minutes)

```bash
# Examine the webhook-enabled inventory configuration
cat inventory/exercise1-3-webhook-config.yml

# Review webhook setup playbook
head -50 playbooks/module1/exercise1-3-webhook-setup.yml
```

#### Step 2: Execute Webhook Simulation (5 minutes)

```bash
# Run the webhook setup and simulation
ansible-playbook playbooks/module1/exercise1-3-webhook-setup.yml

# Test the webhook-enabled inventory
ansible-inventory -i inventory/exercise1-3-webhook-config.yml --list | jq '.webhook_enabled_true // empty'
```

#### Step 3: Understand Production Implementation (3 minutes)

**Key Concepts Demonstrated:**
- **Admission Webhooks:** Automatically trigger inventory refresh on resource changes
- **Circuit Breaker Pattern:** Prevent cascading failures when AAP is unavailable
- **Rate Limiting:** Protect AAP controller from webhook storms
- **Retry Logic:** Handle transient failures gracefully

**Production Deployment Steps:**
1. Configure AAP controller webhook endpoint
2. Deploy admission webhook to OpenShift
3. Set up proper authentication and TLS
4. Implement monitoring and alerting

---

## Exercise 1.4: Troubleshooting and Optimization

**⏱️ Time Allocation:** 5 minutes

### Learning Objectives
- Develop systematic troubleshooting approaches
- Optimize inventory performance for large clusters
- Generate diagnostic reports for inventory issues

### Step-by-Step Instructions

#### Step 1: Run Comprehensive Troubleshooting (3 minutes)

```bash
# Execute the troubleshooting playbook
ansible-playbook playbooks/module1/exercise1-4-troubleshooting.yml

# Review the generated diagnostic report
cat /tmp/inventory-diagnostic-*.txt
```

#### Step 2: Practice Diagnostic Commands (2 minutes)

```bash
# Test inventory performance
time ansible-inventory -i inventory/exercise1-4-optimized-config.yml --list > /dev/null

# Validate inventory groups
ansible-inventory -i inventory/exercise1-4-optimized-config.yml --graph | head -20

# Check for inventory errors
ansible-inventory -i inventory/exercise1-4-optimized-config.yml --list 2>&1 | grep -i error || echo "No errors found"
```

---

## Module 1 Validation Checkpoints

Complete these validation steps to confirm your learning:

### ✅ Checkpoint 1: Basic Inventory Discovery
```bash
# This should return pods grouped by namespace
ansible-inventory -i inventory/exercise1-1-single-cluster.yml --graph | grep namespace_
```

### ✅ Checkpoint 2: Multi-Cluster Grouping
```bash
# This should show cluster-specific groups
ansible-inventory -i inventory/exercise1-2-multi-cluster.yml --list | jq 'keys[]' | grep cluster_
```

### ✅ Checkpoint 3: Webhook Configuration
```bash
# This should show webhook-enabled pods (if any exist)
ansible-inventory -i inventory/exercise1-3-webhook-config.yml --list | jq '.webhook_enabled_true // "No webhook-enabled pods"'
```

### ✅ Checkpoint 4: Troubleshooting Skills
```bash
# This should complete without errors and generate a diagnostic report
ls -la /tmp/inventory-diagnostic-*.txt
```

## Common Issues and Solutions

### Issue 1: "Failed to connect to cluster"
**Symptoms:** Connection refused or timeout errors
**Diagnosis:**
```bash
kubectl cluster-info
kubectl config current-context
```
**Solution:** Verify kubeconfig and network connectivity

### Issue 2: "Permission denied for resource discovery"
**Symptoms:** 403 Forbidden errors
**Diagnosis:**
```bash
kubectl auth can-i get pods
kubectl auth can-i list pods --all-namespaces
```
**Solution:** Check RBAC permissions for your service account

### Issue 3: "No pods in inventory"
**Symptoms:** Empty inventory results
**Diagnosis:**
```bash
kubectl get pods --all-namespaces | grep -v kube-system
```
**Solution:** Check filters in inventory configuration, ensure pods exist

### Issue 4: "Inventory sync timeout"
**Symptoms:** Slow inventory refresh, timeout errors
**Solution:** 
- Implement caching: `cache: true, cache_timeout: 300`
- Add filters to reduce resource queries
- Increase timeout values in connections

## Module 1 Completion Checklist

Before proceeding to Module 2, ensure you can:

- [ ] Configure single-cluster dynamic inventory with proper grouping
- [ ] Set up multi-cluster inventory discovery across environments
- [ ] Understand webhook-based inventory synchronization concepts
- [ ] Troubleshoot common inventory issues systematically
- [ ] Generate diagnostic reports for inventory problems
- [ ] Optimize inventory performance for production use

## Next Steps

**🚀 Ready for Module 2?**

Module 1 has established your dynamic inventory foundation. In Module 2, you'll use these inventory skills to:

- Deploy IMS services across the discovered environments
- Implement idempotent resource management patterns
- Configure automated RBAC provisioning
- Build rollback capabilities for failed deployments

**Estimated prep time for Module 2:** 5 minutes to review prerequisites

## Additional Resources

### Quick Reference Commands
```bash
# List all available inventory plugins
ansible-doc -t inventory -l

# Get help for kubernetes.core.k8s plugin
ansible-doc -t inventory kubernetes.core.k8s

# Validate inventory configuration syntax
ansible-inventory -i <inventory-file> --list --export

# Debug inventory issues with verbose output
ansible-inventory -i <inventory-file> --list -vvv
```

### Advanced Configuration Examples
See the `inventory/` directory for additional configuration examples and optimization techniques suitable for production environments.

---

**⚡ Module 1 Complete!** You now have production-ready dynamic inventory skills for multi-cluster OpenShift environments. Ready to build on this foundation in Module 2!