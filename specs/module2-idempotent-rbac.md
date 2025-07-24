# Module 2: Idempotent Resource Management and RBAC - Exercise PRD

## Executive Summary

This PRD defines the hands-on exercises for **Module 2: Idempotent Resource Management and RBAC** (45 minutes). Participants will implement production-ready resource management patterns using the `redhat.openshift` collection, focusing on idempotent deployments, automated RBAC provisioning, and rollback capabilities for IMS workloads.

## Learning Objectives

By the end of this module, participants will:
1. Implement idempotent deployment patterns using `redhat.openshift` collection
2. Create automated service account provisioning with RBAC binding
3. Build rollback capabilities using `block-rescue-always` patterns
4. Configure security context constraints for IMS workloads
5. Demonstrate true idempotency through repeated executions

## Exercise Structure

### Exercise 2.1: Idempotent Resource Deployment (15 minutes)
**Objective**: Create and manage OpenShift resources with guaranteed idempotency

**Prerequisites:**
- Working multi-cluster inventory from Module 1
- `redhat.openshift` collection installed
- Service accounts with appropriate permissions

**Hands-on Tasks:**
1. Create idempotent namespace management playbook
2. Deploy IMS connector service with proper resource definitions
3. Implement resource update detection and conditional changes
4. Test idempotency by running playbook multiple times

**Expected Deliverable:**
```yaml
# playbooks/idempotent_ocp.yml
- name: Deploy IMS Connector Service Idempotently
  hosts: localhost
  gather_facts: false
  vars:
    ims_namespace: "ims-{{ target_env }}"
    ims_service_name: "ims-connector"
  tasks:
    - name: Ensure IMS namespace exists
      redhat.openshift.k8s:
        name: "{{ ims_namespace }}"
        api_version: v1
        kind: Namespace
        state: present
        definition:
          metadata:
            labels:
              app.kubernetes.io/name: ims-environment
              app.kubernetes.io/environment: "{{ target_env }}"

    - name: Deploy IMS connector service
      redhat.openshift.k8s:
        state: present
        definition:
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: "{{ ims_service_name }}"
            namespace: "{{ ims_namespace }}"
          spec:
            replicas: "{{ ims_replicas | default(2) }}"
            selector:
              matchLabels:
                app: "{{ ims_service_name }}"
            template:
              metadata:
                labels:
                  app: "{{ ims_service_name }}"
              spec:
                containers:
                - name: ims-connector
                  image: "registry.redhat.io/ims/connector:{{ ims_version | default('latest') }}"
                  ports:
                  - containerPort: 8080
                  env:
                  - name: DATABASE_URL
                    valueFrom:
                      secretKeyRef:
                        name: ims-database-secret
                        key: url
        wait: true
        wait_condition:
          type: Available
          status: "True"
        wait_timeout: 300
```

**Validation Checkpoint**: Run playbook 3 times consecutively with no resource conflicts or changes on repeated runs.

### Exercise 2.2: Automated RBAC Provisioning (15 minutes)
**Objective**: Implement comprehensive service account and RBAC automation

**Progressive Complexity:**
- Create environment-specific service accounts
- Bind appropriate cluster and namespace roles
- Implement security context constraints for IMS workloads

**Hands-on Tasks:**
1. Create service account provisioning automation
2. Implement role-based access control bindings
3. Configure security context constraints for mainframe connectivity
4. Test service account permissions and limitations

**Expected Deliverable:**
```yaml
# tasks in playbooks/rbac_automation.yml
- name: Create IMS service account
  redhat.openshift.k8s:
    name: "{{ ims_service_account }}"
    api_version: v1
    kind: ServiceAccount
    namespace: "{{ ims_namespace }}"
    state: present
    definition:
      metadata:
        labels:
          app.kubernetes.io/name: ims-rbac
          app.kubernetes.io/environment: "{{ target_env }}"

- name: Create custom ClusterRole for IMS operations
  redhat.openshift.k8s:
    name: ims-operator
    api_version: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    state: present
    definition:
      rules:
      - apiGroups: [""]
        resources: ["pods", "services", "configmaps", "secrets"]
        verbs: ["get", "list", "create", "update", "patch", "delete"]
      - apiGroups: ["apps"]
        resources: ["deployments", "replicasets"]
        verbs: ["get", "list", "create", "update", "patch", "delete"]
      - apiGroups: ["networking.k8s.io"]
        resources: ["networkpolicies"]
        verbs: ["get", "list", "create", "update", "patch", "delete"]

- name: Bind ClusterRole to service account
  redhat.openshift.k8s:
    name: "{{ ims_service_account }}-binding"
    api_version: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    state: present
    definition:
      subjects:
      - kind: ServiceAccount
        name: "{{ ims_service_account }}"
        namespace: "{{ ims_namespace }}"
      roleRef:
        kind: ClusterRole
        name: ims-operator
        apiGroup: rbac.authorization.k8s.io

- name: Create SecurityContextConstraints for IMS
  redhat.openshift.k8s:
    name: ims-scc
    api_version: security.openshift.io/v1
    kind: SecurityContextConstraints
    state: present
    definition:
      allowHostDirVolumePlugin: false
      allowHostIPC: false
      allowHostNetwork: false
      allowHostPID: false
      allowPrivilegedContainer: false
      allowedCapabilities: []
      defaultAddCapabilities: []
      fsGroup:
        type: RunAsAny
      readOnlyRootFilesystem: false
      requiredDropCapabilities: ["ALL"]
      runAsUser:
        type: MustRunAsRange
        uidRangeMin: 1000
        uidRangeMax: 2000
      seLinuxContext:
        type: MustRunAs
      users:
      - "system:serviceaccount:{{ ims_namespace }}:{{ ims_service_account }}"
```

**Validation Checkpoint**: Service account can successfully deploy resources with proper security constraints applied.

### Exercise 2.3: Error Handling and Rollback Mechanisms (10 minutes)
**Objective**: Implement production-ready error handling with automatic rollback capabilities

**Advanced Patterns:**
- Use `block-rescue-always` for transaction-like behavior
- Implement deployment verification and automatic rollback
- Handle partial failures gracefully

**Hands-on Tasks:**
1. Wrap deployment tasks in error handling blocks
2. Create rollback procedures for failed deployments
3. Implement health checks and validation
4. Test failure scenarios and recovery

**Expected Deliverable:**
```yaml
# Error handling pattern in playbooks/idempotent_ocp.yml
- name: Deploy IMS Environment with Rollback
  block:
    - name: Store current deployment state
      redhat.openshift.k8s_info:
        api_version: apps/v1
        kind: Deployment
        name: "{{ ims_service_name }}"
        namespace: "{{ ims_namespace }}"
      register: current_deployment
      ignore_errors: true

    - name: Deploy new IMS connector version
      redhat.openshift.k8s:
        state: present
        definition: "{{ ims_deployment_spec }}"
        wait: true
        wait_condition:
          type: Available
          status: "True"
        wait_timeout: 300
      register: deployment_result

    - name: Validate deployment health
      uri:
        url: "http://{{ ims_service_name }}.{{ ims_namespace }}.svc.cluster.local:8080/health"
        method: GET
        status_code: 200
      retries: 5
      delay: 10

  rescue:
    - name: Log deployment failure
      debug:
        msg: "Deployment failed: {{ ansible_failed_result.msg }}"

    - name: Rollback to previous deployment
      redhat.openshift.k8s:
        state: present
        definition: "{{ current_deployment.resources[0] }}"
      when: current_deployment.resources | length > 0

    - name: Fail the playbook with meaningful error
      fail:
        msg: "IMS deployment failed and was rolled back. Check logs for details."

  always:
    - name: Clean up temporary resources
      redhat.openshift.k8s:
        api_version: v1
        kind: ConfigMap
        name: "{{ ims_service_name }}-temp-config"
        namespace: "{{ ims_namespace }}"
        state: absent
      ignore_errors: true

    - name: Record deployment attempt
      copy:
        content: |
          Deployment attempt: {{ ansible_date_time.iso8601 }}
          Target environment: {{ target_env }}
          Status: {{ 'success' if deployment_result is succeeded else 'failed' }}
        dest: "/tmp/ims-deployment-{{ target_env }}.log"
      delegate_to: localhost
```

**Validation Checkpoint**: Demonstrate successful rollback when deployment validation fails.

### Exercise 2.4: IMS-Specific Configuration (5 minutes)
**Objective**: Apply workshop learnings to realistic IMS deployment scenarios

**Real-world Integration:**
- Mainframe connectivity configuration
- Database connection pooling
- Legacy system integration patterns

**Hands-on Tasks:**
1. Configure IMS-specific environment variables and secrets
2. Set up network policies for mainframe connectivity
3. Create persistent volume claims for IMS data
4. Implement monitoring and logging configuration

**Expected Deliverable:**
```yaml
# IMS-specific configuration tasks
- name: Create IMS database secret
  redhat.openshift.k8s:
    definition:
      apiVersion: v1
      kind: Secret
      metadata:
        name: ims-database-secret
        namespace: "{{ ims_namespace }}"
      type: Opaque
      stringData:
        url: "{{ ims_database_url }}"
        username: "{{ ims_database_user }}"
        password: "{{ ims_database_password }}"
        pool_size: "{{ ims_connection_pool_size | default('10') }}"

- name: Configure network policy for mainframe access
  redhat.openshift.k8s:
    definition:
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      metadata:
        name: ims-mainframe-access
        namespace: "{{ ims_namespace }}"
      spec:
        podSelector:
          matchLabels:
            app: "{{ ims_service_name }}"
        policyTypes:
        - Egress
        egress:
        - to:
          - namespaceSelector: {}
          ports:
          - protocol: TCP
            port: 8080
        - to: []  # Allow mainframe connectivity
          ports:
          - protocol: TCP
            port: 9999  # IMS port

- name: Create persistent storage for IMS logs
  redhat.openshift.k8s:
    definition:
      apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: ims-logs-pvc
        namespace: "{{ ims_namespace }}"
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: "{{ ims_log_storage_size | default('10Gi') }}"
        storageClassName: fast-ssd
```

## Technical Requirements

### Environment Setup
**Multi-Environment Configuration:**
- Development: 2 replica pods, 4GB RAM limit
- Testing: 3 replica pods, 8GB RAM limit
- Production: 5 replica pods, 16GB RAM limit

**RBAC Prerequisites:**
```bash
# Grant workshop participants necessary cluster permissions
oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:workshop:participant-sa
```

### Collection Dependencies
```yaml
# collections/requirements.yml
collections:
  - name: redhat.openshift
    version: ">=2.2.0"
  - name: kubernetes.core
    version: ">=2.4.0"
  - name: community.general
    version: ">=5.0.0"
```

### Resource Quotas per Environment
```yaml
# quota-template.yml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ims-quota
spec:
  hard:
    requests.cpu: "{{ environment_cpu_request }}"
    requests.memory: "{{ environment_memory_request }}"
    limits.cpu: "{{ environment_cpu_limit }}"
    limits.memory: "{{ environment_memory_limit }}"
    persistentvolumeclaims: "5"
    services: "10"
```

## Assessment Criteria

### Idempotency Validation
- [ ] Playbook runs successfully multiple times without errors
- [ ] Resources maintain consistent state across runs
- [ ] No spurious changes reported on repeated execution
- [ ] Conditional logic prevents unnecessary updates

### RBAC Implementation
- [ ] Service accounts created with least-privilege access
- [ ] Security context constraints properly applied
- [ ] Network policies restrict unnecessary connectivity
- [ ] Role bindings follow environment-specific patterns

### Error Handling
- [ ] Failed deployments trigger automatic rollback
- [ ] Partial failures handled gracefully
- [ ] Health checks validate deployment success
- [ ] Meaningful error messages provided to operators

## Troubleshooting Scenarios

### Scenario 1: Service Account Permission Denied
**Symptoms**: "Forbidden: User cannot create resource"
**Diagnosis Steps**: Check RBAC bindings and cluster role permissions
**Resolution**: Verify service account has necessary cluster-admin or custom role

### Scenario 2: Deployment Rollback Failure
**Symptoms**: New deployment fails but rollback also fails
**Resolution**: Implement backup state storage and manual intervention procedures

### Scenario 3: Resource Quota Exceeded
**Symptoms**: "Exceeded quota: requests.memory"
**Resolution**: Implement resource limit validation and environment-appropriate sizing

## Progressive Skill Building

### Novice Support
- Pre-configured RBAC templates
- Guided troubleshooting worksheets
- Validation scripts to check configuration

### Advanced Challenges
- Custom operator development using operator-sdk
- GitOps integration with ArgoCD
- Multi-cluster resource synchronization

## Integration with Module 3

**Output Artifacts:**
- Working idempotent deployment playbooks
- RBAC configuration templates
- Error handling patterns for complex scenarios
- IMS-specific configuration examples

**Prerequisites for Module 3:**
- Reliable deployment capabilities
- Service account authentication
- Error handling foundation for advanced automation

This module establishes production-ready deployment patterns essential for enterprise IMS environments while building the foundation for advanced automation and troubleshooting techniques.