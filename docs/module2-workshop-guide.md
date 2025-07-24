# Module 2: Idempotent Resource Management and RBAC - Workshop Guide

## Overview

**Duration:** 45 minutes  
**Objective:** Master production-ready resource management patterns using the `redhat.openshift` collection with comprehensive RBAC automation and rollback capabilities

In this module, you'll progress from basic resource deployment to enterprise-grade idempotent patterns, automated service account provisioning, and robust error handling for IMS workloads in OpenShift environments.

## Prerequisites

Before starting this module, ensure you have:

- [ ] Completed Module 1 with working dynamic inventory
- [ ] OpenShift cluster access with cluster-admin permissions
- [ ] `redhat.openshift` collection installed (`ansible-galaxy collection install redhat.openshift`)
- [ ] `kubernetes.core` collection available from Module 1
- [ ] Understanding of RBAC concepts and security context constraints

### Quick Environment Check

```bash
# Verify redhat.openshift collection
ansible-galaxy collection list | grep redhat.openshift

# Check cluster-admin permissions
oc auth can-i create clusterroles
oc auth can-i create securitycontextconstraints

# Verify namespace creation permissions
oc auth can-i create namespaces

# Test Module 1 inventory is still working
ansible-inventory -i inventory/exercise1-2-multi-cluster.yml --list | jq 'keys[]' | head -5
```

## Module Structure

| Exercise | Duration | Focus Area |
|----------|----------|------------|
| 2.1 | 15 min | Idempotent Resource Deployment |
| 2.2 | 15 min | Automated RBAC Provisioning |
| 2.3 | 10 min | Error Handling and Rollback Mechanisms |
| 2.4 | 5 min | IMS-Specific Configuration and Validation |

---

## Exercise 2.1: Idempotent Resource Deployment

**⏱️ Time Allocation:** 15 minutes (10 min hands-on, 5 min validation)

### Learning Objectives
- Implement truly idempotent deployment patterns using `redhat.openshift.k8s`
- Create environment-aware resource management with conditional changes
- Build deployment verification and state management capabilities

### Step-by-Step Instructions

#### Step 1: Review the Idempotent Deployment Configuration (3 minutes)

```bash
# Examine the idempotent deployment playbook
cat playbooks/module2/exercise2-1-idempotent-deployment.yml

# Review the IMS deployment role structure
ls -la roles/ims_deployment/
```

**Key Idempotency Concepts:**
- `state: present` - Ensures resources exist with desired configuration
- `wait: true` and `wait_condition` - Validates deployment success before continuing
- `definition` blocks - Declare desired state rather than imperative commands
- Resource comparison - Only updates when actual state differs from desired state

#### Step 2: Deploy IMS Services Idempotently (7 minutes)

```bash
# Run the idempotent deployment for development environment
ansible-playbook playbooks/module2/exercise2-1-idempotent-deployment.yml \
  -e target_env=dev \
  -e ims_version=1.0.0

# Run the same playbook again to test idempotency
ansible-playbook playbooks/module2/exercise2-1-idempotent-deployment.yml \
  -e target_env=dev \
  -e ims_version=1.0.0

# Check deployment status
oc get deployment -n ims-dev ims-connector -o wide
```

#### Step 3: Test Configuration Changes and Updates (5 minutes)

```bash
# Update to a new version to test rolling updates
ansible-playbook playbooks/module2/exercise2-1-idempotent-deployment.yml \
  -e target_env=dev \
  -e ims_version=1.1.0

# Verify the update was applied correctly
oc describe deployment -n ims-dev ims-connector | grep "Image:"

# Scale the deployment and verify idempotency
ansible-playbook playbooks/module2/exercise2-1-idempotent-deployment.yml \
  -e target_env=dev \
  -e ims_version=1.1.0 \
  -e ims_replicas=3
```

#### Step 4: Validation Checkpoint (5 minutes)

**Expected Results:**
- ✅ First playbook run creates all resources successfully
- ✅ Second identical run reports no changes (idempotent behavior)
- ✅ Version update triggers rolling deployment without errors
- ✅ Scaling changes are applied correctly and reported

**Troubleshooting Common Issues:**

| Issue | Symptoms | Solution |
|-------|----------|----------|
| Resources not created | "Failed to create resource" | Check RBAC permissions: `oc auth can-i create deployments` |
| Updates not applied | No changes on version update | Verify resource comparison logic in playbook |
| Deployment stuck | Pods not ready after wait timeout | Check resource limits and image availability |

---

## Exercise 2.2: Automated RBAC Provisioning

**⏱️ Time Allocation:** 15 minutes (10 min configuration, 5 min testing)

### Learning Objectives
- Automate service account provisioning with least-privilege access
- Implement security context constraints for IMS workloads
- Create environment-specific RBAC patterns

### Step-by-Step Instructions

#### Step 1: Review RBAC Automation Structure (3 minutes)

```bash
# Examine the RBAC automation playbook
cat playbooks/module2/exercise2-2-rbac-automation.yml

# Review the RBAC role templates
ls -la roles/ims_rbac/tasks/
cat roles/ims_rbac/tasks/main.yml
```

**Key RBAC Components:**
- **ServiceAccount** - Identity for IMS applications
- **ClusterRole** - Permissions for cross-namespace operations
- **ClusterRoleBinding** - Links service accounts to cluster roles
- **SecurityContextConstraints** - OpenShift-specific security policies

#### Step 2: Execute RBAC Provisioning (7 minutes)

```bash
# Run RBAC automation for development environment
ansible-playbook playbooks/module2/exercise2-2-rbac-automation.yml \
  -e target_env=dev

# Verify service account creation
oc get serviceaccount -n ims-dev ims-operator

# Check cluster role and bindings
oc get clusterrole ims-operator
oc get clusterrolebinding | grep ims-operator

# Verify security context constraints
oc get scc ims-scc -o yaml
```

#### Step 3: Test Service Account Permissions (5 minutes)

```bash
# Test service account can create required resources
oc auth can-i create pods --as=system:serviceaccount:ims-dev:ims-operator
oc auth can-i create services --as=system:serviceaccount:ims-dev:ims-operator
oc auth can-i create networkpolicies --as=system:serviceaccount:ims-dev:ims-operator

# Test restricted permissions (should be denied)
oc auth can-i create clusterroles --as=system:serviceaccount:ims-dev:ims-operator
oc auth can-i delete nodes --as=system:serviceaccount:ims-dev:ims-operator
```

**Expected Permission Matrix:**
- ✅ Create/manage pods, services, configmaps, secrets in IMS namespaces
- ✅ Create/manage deployments and replicasets
- ✅ Create/manage network policies
- ❌ Create cluster-level resources (except those explicitly granted)
- ❌ Access system namespaces or privileged operations

---

## Exercise 2.3: Error Handling and Rollback Mechanisms

**⏱️ Time Allocation:** 10 minutes (6 min implementation, 4 min testing)

### Learning Objectives
- Implement production-grade error handling with `block-rescue-always` patterns
- Create automatic rollback capabilities for failed deployments
- Build comprehensive deployment validation and health checking

### Step-by-Step Instructions

#### Step 1: Review Error Handling Patterns (2 minutes)

```bash
# Examine the rollback patterns playbook
cat playbooks/module2/exercise2-3-rollback-patterns.yml

# Review the validation tasks
grep -A 20 "Validate deployment health" playbooks/module2/exercise2-3-rollback-patterns.yml
```

#### Step 2: Test Successful Deployment with Error Handling (4 minutes)

```bash
# Run deployment with comprehensive error handling
ansible-playbook playbooks/module2/exercise2-3-rollback-patterns.yml \
  -e target_env=dev \
  -e ims_version=1.2.0

# Check the deployment logs for error handling execution
tail -20 /tmp/ims-deployment-dev.log
```

#### Step 3: Simulate and Test Failure Scenarios (4 minutes)

```bash
# Test rollback with intentionally broken image
ansible-playbook playbooks/module2/exercise2-3-rollback-patterns.yml \
  -e target_env=dev \
  -e ims_version=broken-tag \
  -e ims_image_repo=nonexistent-registry.com/ims/connector

# Verify rollback occurred
oc get deployment -n ims-dev ims-connector -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check rollback logs
tail -30 /tmp/ims-deployment-dev.log
```

**Expected Behavior:**
- ✅ Successful deployments complete without triggering rescue blocks
- ✅ Failed deployments automatically rollback to previous working state
- ✅ Health checks validate deployment success before marking complete
- ✅ Comprehensive logging captures all deployment attempts

---

## Exercise 2.4: IMS-Specific Configuration and Validation

**⏱️ Time Allocation:** 5 minutes

### Learning Objectives
- Apply enterprise patterns to realistic IMS deployment scenarios
- Configure mainframe connectivity and security requirements
- Validate complete end-to-end IMS environment

### Step-by-Step Instructions

#### Step 1: Deploy Complete IMS Configuration (3 minutes)

```bash
# Run the comprehensive validation playbook
ansible-playbook playbooks/module2/exercise2-4-validation.yml \
  -e target_env=dev

# Verify all IMS components are running
oc get all -n ims-dev -l app.kubernetes.io/name=ims-environment
```

#### Step 2: Validate IMS Environment (2 minutes)

```bash
# Test IMS service endpoints
oc port-forward -n ims-dev service/ims-connector 8080:8080 &
curl -s http://localhost:8080/health | jq

# Check IMS-specific network policies
oc get networkpolicy -n ims-dev ims-mainframe-access -o yaml

# Verify persistent storage configuration
oc get pvc -n ims-dev
```

---

## Module 2 Validation Checkpoints

Complete these validation steps to confirm your learning:

### ✅ Checkpoint 1: Idempotent Deployment
```bash
# This should show no changes on repeated execution
ansible-playbook playbooks/module2/exercise2-1-idempotent-deployment.yml \
  -e target_env=dev -e ims_version=1.2.0 | grep "changed=0"
```

### ✅ Checkpoint 2: RBAC Automation
```bash
# This should return "yes" for required permissions
oc auth can-i create deployments --as=system:serviceaccount:ims-dev:ims-operator
```

### ✅ Checkpoint 3: Error Handling
```bash
# This should show successful rollback logs
grep -i "rollback" /tmp/ims-deployment-dev.log
```

### ✅ Checkpoint 4: Complete IMS Environment
```bash
# This should show healthy IMS services
oc get deployment -n ims-dev ims-connector -o jsonpath='{.status.readyReplicas}'
```

## Common Issues and Solutions

### Issue 1: "Forbidden: User cannot create ClusterRole"
**Symptoms:** Permission denied errors during RBAC creation
**Diagnosis:**
```bash
oc auth can-i create clusterroles
oc whoami
```
**Solution:** Ensure your user has cluster-admin permissions or appropriate RBAC roles

### Issue 2: "SecurityContextConstraints admission denied"
**Symptoms:** Pods fail to start with security policy violations
**Diagnosis:**
```bash
oc get events -n ims-dev | grep -i security
oc describe pod <pod-name> -n ims-dev
```
**Solution:** Verify SCC is properly created and service account is authorized

### Issue 3: "Deployment rollout stuck"
**Symptoms:** Deployments remain in "Progressing" state
**Diagnosis:**
```bash
oc rollout status deployment/ims-connector -n ims-dev
oc get pods -n ims-dev -l app=ims-connector
```
**Solution:** Check resource quotas, image availability, and health check configurations

### Issue 4: "Rollback failed to restore previous state"
**Symptoms:** Error handling doesn't properly restore working deployment
**Solution:**
- Ensure deployment state is captured before changes
- Verify `current_deployment.resources` contains valid previous state
- Check that rollback deployment definition is complete

## Module 2 Completion Checklist

Before proceeding to Module 3, ensure you can:

- [ ] Deploy OpenShift resources idempotently with no changes on repeated runs
- [ ] Create and manage service accounts with appropriate RBAC permissions
- [ ] Implement security context constraints for IMS workloads
- [ ] Handle deployment failures with automatic rollback capabilities
- [ ] Configure IMS-specific networking and storage requirements
- [ ] Validate deployment health and connectivity systematically

## Next Steps

**🚀 Ready for Module 3?**

Module 2 has established your production-ready deployment foundation. In Module 3, you'll enhance these capabilities with:

- Advanced Jinja2 templating for complex environment configurations
- Sophisticated error handling with circuit breaker patterns
- Automated testing using the Molecule framework
- Advanced troubleshooting techniques for production environments

**Estimated prep time for Module 3:** 5 minutes to review Jinja2 templating concepts

## Additional Resources

### Quick Reference Commands
```bash
# Test resource idempotency
ansible-playbook <playbook> --check --diff

# Validate RBAC permissions
oc auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<sa-name>

# Debug deployment issues
oc rollout history deployment/<name> -n <namespace>
oc rollout undo deployment/<name> -n <namespace>

# Monitor resource events
oc get events -n <namespace> --sort-by=.metadata.creationTimestamp
```

### Production Deployment Patterns
See the `roles/ims_deployment/` and `roles/ims_rbac/` directories for reusable automation patterns suitable for enterprise environments.

---

**⚡ Module 2 Complete!** You now have enterprise-grade deployment capabilities with comprehensive RBAC and error handling. Ready to add advanced automation in Module 3!