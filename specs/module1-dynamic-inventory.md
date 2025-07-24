# Module 1: Dynamic Inventory and AAP Integration - Exercise PRD

## Executive Summary

This PRD defines the hands-on exercises for **Module 1: Dynamic Inventory and AAP Integration** (40 minutes). Participants will implement advanced inventory management patterns for multi-cluster OpenShift environments, progressing from basic single-cluster inventory to complex event-driven inventory updates.

## Learning Objectives

By the end of this module, participants will:
1. Configure constructed inventories combining multiple OpenShift clusters
2. Implement OpenShift service discovery using the `kubernetes.core` collection
3. Set up automated inventory synchronization with API webhooks
4. Troubleshoot common inventory sync failures and timeout issues
5. Query hosts across different cluster environments with dynamic grouping

## Exercise Structure

### Exercise 1.1: Single-Cluster Dynamic Inventory (10 minutes)
**Objective**: Establish baseline inventory management using `kubernetes.core.k8s_info`

**Prerequisites:**
- OpenShift cluster access with service account tokens
- AAP 2.5 with `kubernetes.core` collection installed
- Basic understanding of Ansible inventory concepts

**Hands-on Tasks:**
1. Create inventory plugin configuration for single OpenShift cluster
2. Configure authentication using service account tokens
3. Test basic pod and service discovery
4. Implement namespace-based grouping

**Expected Deliverable:**
```yaml
# inventory/openshift.yml
plugin: kubernetes.core.k8s
connections:
  - kubeconfig: ~/.kube/config
    context: cluster-dev
compose:
  ansible_host: status.podIP
keyed_groups:
  - key: metadata.namespace
    prefix: namespace
  - key: metadata.labels['app']
    prefix: app
```

**Validation Checkpoint**: Successfully query and group pods by namespace and application labels.

### Exercise 1.2: Multi-Cluster Inventory Configuration (15 minutes)
**Objective**: Extend inventory to manage three OpenShift clusters (dev/test/prod)

**Progressive Complexity:**
- Start with static cluster definitions
- Add cluster-specific connection parameters
- Implement cross-cluster resource discovery

**Hands-on Tasks:**
1. Configure inventory for three clusters with different contexts
2. Set up cluster-specific authentication methods
3. Create composite groups spanning multiple clusters
4. Test cross-cluster service discovery

**Expected Deliverable:**
```yaml
# inventory/multi-cluster.yml
plugin: kubernetes.core.k8s
connections:
  - kubeconfig: ~/.kube/config
    context: cluster-dev
  - kubeconfig: ~/.kube/config
    context: cluster-test  
  - kubeconfig: ~/.kube/config
    context: cluster-prod
compose:
  cluster_name: connection.context
  ansible_host: status.podIP
keyed_groups:
  - key: connection.context
    prefix: cluster
  - key: metadata.namespace + "_" + connection.context
    prefix: ns_cluster
```

**Validation Checkpoint**: Query resources across all three clusters with proper cluster identification.

### Exercise 1.3: Event-Driven Inventory Updates (10 minutes)
**Objective**: Implement automated inventory synchronization using OpenShift API webhooks

**Advanced Integration:**
- Configure webhook endpoints in AAP
- Set up OpenShift resource watches
- Handle inventory refresh triggers

**Hands-on Tasks:**
1. Create webhook configuration in AAP automation controller
2. Set up OpenShift admission controllers for inventory triggers
3. Configure refresh intervals and retry logic
4. Test automated updates when resources change

**Expected Deliverable:**
```yaml
# webhook-config.yml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingAdmissionWebhook
metadata:
  name: inventory-sync-webhook
webhooks:
- name: pods.inventory.sync
  clientConfig:
    url: "https://aap-controller.example.com/api/v2/inventory_sources/1/update/"
  rules:
  - operations: ["CREATE", "UPDATE", "DELETE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
```

**Validation Checkpoint**: Demonstrate automatic inventory refresh when pods are created/deleted.

### Exercise 1.4: Troubleshooting and Optimization (5 minutes)
**Objective**: Diagnose and resolve common inventory management issues

**Common Scenarios:**
- Authentication token expiration
- Network connectivity timeouts
- Resource permission errors
- Large cluster performance issues

**Troubleshooting Tasks:**
1. Debug failed inventory sync using Ansible verbose output
2. Resolve service account permission issues
3. Optimize inventory queries for large clusters
4. Implement error handling and retry mechanisms

**Expected Deliverable:**
```yaml
# inventory/optimized-config.yml
plugin: kubernetes.core.k8s
connections:
  - kubeconfig: ~/.kube/config
    context: cluster-prod
cache: true
cache_plugin: memory
cache_timeout: 300
filters:
  - metadata.namespace != "kube-system"
  - status.phase == "Running"
strict: false
```

## Technical Requirements

### Environment Setup
**Per Participant:**
- 3 OpenShift cluster contexts (dev/test/prod namespaces)
- Service account with cluster-reader permissions minimum
- AAP 2.5 automation controller access
- Webhook endpoint configuration capability

**Resource Allocation:**
- Dev cluster: 10 pods across 3 namespaces
- Test cluster: 20 pods across 5 namespaces  
- Prod cluster: 50 pods across 10 namespaces

### Collection Dependencies
```yaml
# collections/requirements.yml
collections:
  - name: kubernetes.core
    version: ">=2.4.0"
  - name: ansible.posix
    version: ">=1.4.0"
```

### Authentication Configuration
**Service Account Setup:**
```bash
# Create service accounts per cluster
for cluster in dev test prod; do
  oc create serviceaccount inventory-reader -n default --context=cluster-${cluster}
  oc adm policy add-cluster-role-to-user view system:serviceaccount:default:inventory-reader --context=cluster-${cluster}
done
```

## Assessment Criteria

### Functional Requirements
- [ ] Successfully configure single-cluster inventory discovery
- [ ] Implement multi-cluster inventory with proper grouping
- [ ] Set up automated inventory synchronization
- [ ] Demonstrate troubleshooting skills for common issues

### Performance Requirements
- Inventory refresh completes within 30 seconds for all clusters
- Memory usage remains under 512MB during inventory operations
- Network timeouts handled gracefully with retry logic

### Security Requirements
- Service account tokens stored securely (not in playbooks)
- Least-privilege access implemented for inventory operations
- Webhook endpoints use HTTPS with proper authentication

## Progressive Skill Building

### Scaffolding Support
**For Novice Participants:**
- Pre-configured cluster contexts and service accounts
- Template inventory files with TODO comments
- Step-by-step validation scripts

**For Advanced Participants:**
- Custom inventory plugin development challenges
- Performance optimization exercises
- Integration with external CMDB systems

### Knowledge Transfer Validation
**Peer Teaching Moment:**
Participants explain their inventory configuration to a partner, covering:
- Authentication method selection rationale
- Grouping strategy for their use case
- Troubleshooting approach for failed syncs

## Common Issues and Solutions

### Issue: "Failed to connect to cluster"
**Diagnosis**: Check service account token validity and network connectivity
**Solution**: Verify kubeconfig context and test with `oc whoami`

### Issue: "Inventory sync timeout"
**Diagnosis**: Large cluster with too many resources being queried
**Solution**: Implement filters and caching strategies

### Issue: "Permission denied for resource discovery"
**Diagnosis**: Service account lacks necessary RBAC permissions
**Solution**: Add cluster-reader role or create custom role with specific permissions

## Integration with Subsequent Modules

**Module 2 Dependencies:**
- Working multi-cluster inventory provides target hosts
- Service account authentication carries forward
- Dynamic grouping enables environment-specific deployments

**Output Artifacts:**
- `inventory/` directory with working configurations
- Service account setup documentation
- Troubleshooting playbook for inventory issues

This exercise establishes the foundation for all subsequent workshop activities by ensuring participants can reliably discover and manage OpenShift resources across multiple cluster environments.