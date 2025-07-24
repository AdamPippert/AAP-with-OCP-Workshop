# Module 3: Advanced Automation and Error Handling - Exercise PRD

## Executive Summary

This PRD defines the hands-on exercises for **Module 3: Advanced Automation and Error Handling** (45 minutes). Participants will implement complex Jinja2 templating, comprehensive error handling patterns, automated testing using the Molecule framework, and debug intentionally broken IMS deployment scenarios to develop production-ready troubleshooting skills.

## Learning Objectives

By the end of this module, participants will:
1. Build complex Jinja2 templates for environment-specific OpenShift configurations
2. Implement comprehensive error handling with retry mechanisms and state validation
3. Create automated testing pipelines using the Molecule framework
4. Debug and resolve intentionally broken IMS deployment scenarios
5. Develop systematic troubleshooting approaches for production environments

## Exercise Structure

### Exercise 3.1: Advanced Jinja2 Templating (15 minutes)
**Objective**: Create dynamic, environment-aware OpenShift resource definitions using advanced Jinja2 patterns

**Prerequisites:**
- Completed Modules 1 and 2 with working deployments
- Understanding of Jinja2 basics and OpenShift resource structure
- Access to multi-environment cluster configurations

**Hands-on Tasks:**
1. Create environment-specific configuration templates
2. Implement conditional resource generation based on cluster capabilities
3. Build complex data transformations for IMS connectivity
4. Generate dynamic service mesh configurations

**Expected Deliverable:**
```yaml
# templates/ims-deployment.j2
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ ims_service_name }}
  namespace: {{ ims_namespace }}
  labels:
    app.kubernetes.io/name: {{ ims_service_name }}
    app.kubernetes.io/version: {{ ims_version }}
    app.kubernetes.io/environment: {{ target_env }}
    {% if target_env == 'prod' %}
    app.kubernetes.io/managed-by: gitops
    {% endif %}
spec:
  replicas: {{ environment_config[target_env].replicas }}
  strategy:
    type: {{ 'RollingUpdate' if target_env != 'prod' else 'BlueGreen' }}
    {% if target_env == 'prod' %}
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 0
    {% endif %}
  selector:
    matchLabels:
      app: {{ ims_service_name }}
  template:
    metadata:
      labels:
        app: {{ ims_service_name }}
        version: {{ ims_version }}
      annotations:
        {% for key, value in pod_annotations.items() %}
        {{ key }}: "{{ value }}"
        {% endfor %}
    spec:
      serviceAccountName: {{ ims_service_account }}
      securityContext:
        {% if target_env == 'prod' %}
        runAsNonRoot: true
        runAsUser: {{ security_config.prod_user_id }}
        fsGroup: {{ security_config.prod_group_id }}
        {% else %}
        runAsUser: 1001
        {% endif %}
      containers:
      - name: ims-connector
        image: "{{ container_registry }}/ims/connector:{{ ims_version }}"
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 9999
          name: ims-port
        env:
        {% for env_var in base_environment_vars %}
        - name: {{ env_var.name }}
          value: "{{ env_var.value }}"
        {% endfor %}
        {% for secret_var in secret_environment_vars %}
        - name: {{ secret_var.name }}
          valueFrom:
            secretKeyRef:
              name: {{ secret_var.secret_name }}
              key: {{ secret_var.key }}
        {% endfor %}
        resources:
          requests:
            memory: "{{ environment_config[target_env].memory_request }}"
            cpu: "{{ environment_config[target_env].cpu_request }}"
          limits:
            memory: "{{ environment_config[target_env].memory_limit }}"
            cpu: "{{ environment_config[target_env].cpu_limit }}"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: {{ health_check_config[target_env].initial_delay }}
          periodSeconds: {{ health_check_config[target_env].period }}
          timeoutSeconds: {{ health_check_config[target_env].timeout }}
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: {{ health_check_config[target_env].ready_delay }}
          periodSeconds: 5
        {% if persistent_storage_required %}
        volumeMounts:
        - name: ims-data
          mountPath: /data
        - name: ims-logs
          mountPath: /logs
        {% endif %}
      {% if persistent_storage_required %}
      volumes:
      - name: ims-data
        persistentVolumeClaim:
          claimName: ims-data-pvc
      - name: ims-logs
        persistentVolumeClaim:
          claimName: ims-logs-pvc
      {% endif %}
      {% if target_env == 'prod' %}
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - {{ ims_service_name }}
            topologyKey: kubernetes.io/hostname
      {% endif %}
```

**Complex Variables File:**
```yaml
# group_vars/all/ims_config.yml
environment_config:
  dev:
    replicas: 1
    memory_request: "256Mi"
    memory_limit: "512Mi"
    cpu_request: "100m"
    cpu_limit: "200m"
  test:
    replicas: 2
    memory_request: "512Mi"
    memory_limit: "1Gi"
    cpu_request: "200m"
    cpu_limit: "500m"
  prod:
    replicas: 3
    memory_request: "1Gi"
    memory_limit: "2Gi"
    cpu_request: "500m"
    cpu_limit: "1000m"

health_check_config:
  dev:
    initial_delay: 30
    period: 30
    timeout: 5
    ready_delay: 15
  test:
    initial_delay: 45
    period: 20
    timeout: 10
    ready_delay: 20
  prod:
    initial_delay: 60
    period: 15
    timeout: 15
    ready_delay: 30

base_environment_vars:
  - name: ENVIRONMENT
    value: "{{ target_env }}"
  - name: LOG_LEVEL
    value: "{{ 'DEBUG' if target_env != 'prod' else 'INFO' }}"
  - name: IMS_HOST
    value: "{{ ims_mainframe_hosts[target_env] }}"

secret_environment_vars:
  - name: DATABASE_PASSWORD
    secret_name: ims-database-secret
    key: password
  - name: IMS_API_KEY
    secret_name: ims-api-secret
    key: api_key
```

**Validation Checkpoint**: Generate different deployment configurations for dev/test/prod with appropriate resource allocation and security settings.

### Exercise 3.2: Comprehensive Error Handling and Retry Logic (15 minutes)
**Objective**: Implement production-grade error handling with intelligent retry mechanisms and state validation

**Advanced Patterns:**
- Exponential backoff for transient failures
- Circuit breaker patterns for external dependencies
- State validation and repair mechanisms
- Comprehensive logging and alerting

**Hands-on Tasks:**
1. Implement retry logic with exponential backoff
2. Create circuit breaker pattern for IMS connectivity
3. Build state validation and repair automation
4. Develop comprehensive error logging and alerting

**Expected Deliverable:**
```yaml
# playbooks/error_handling.yml
- name: Deploy IMS with Advanced Error Handling
  hosts: localhost
  gather_facts: false
  vars:
    max_retries: 3
    base_delay: 2
    max_delay: 30
    circuit_breaker_threshold: 5
    
  tasks:
    - name: Initialize error tracking
      set_fact:
        error_count: 0
        circuit_open: false
        deployment_start_time: "{{ ansible_date_time.epoch }}"

    - name: Deploy IMS with retry logic
      block:
        - name: Attempt IMS deployment
          include_tasks: tasks/deploy_ims_with_validation.yml
          vars:
            attempt_number: "{{ ansible_loop.index }}"
          register: deployment_result
          until: deployment_result is succeeded
          retries: "{{ max_retries }}"
          delay: "{{ [base_delay * (2 ** (ansible_loop.index - 1)), max_delay] | min }}"
          loop: "{{ range(1, max_retries + 1) | list }}"
          loop_control:
            index_var: retry_attempt

      rescue:
        - name: Log deployment failure details
          debug:
            msg: |
              IMS Deployment Failed:
              - Attempt: {{ retry_attempt | default(1) }}
              - Error: {{ ansible_failed_result.msg }}
              - Failed Task: {{ ansible_failed_task.name }}
              - Duration: {{ (ansible_date_time.epoch | int) - (deployment_start_time | int) }}s

        - name: Check if circuit breaker should open
          set_fact:
            error_count: "{{ (error_count | int) + 1 }}"

        - name: Open circuit breaker
          set_fact:
            circuit_open: true
          when: error_count | int >= circuit_breaker_threshold

        - name: Send failure notification
          uri:
            url: "{{ alerting_webhook_url }}"
            method: POST
            body_format: json
            body:
              alert_type: "deployment_failure"
              service: "{{ ims_service_name }}"
              environment: "{{ target_env }}"
              error_count: "{{ error_count }}"
              circuit_breaker_status: "{{ 'open' if circuit_open else 'closed' }}"
              timestamp: "{{ ansible_date_time.iso8601 }}"
          when: alerting_webhook_url is defined

        - name: Fail with comprehensive error information
          fail:
            msg: |
              IMS deployment failed after {{ max_retries }} attempts.
              Circuit breaker status: {{ 'OPEN' if circuit_open else 'CLOSED' }}
              Total errors in window: {{ error_count }}
              Check logs at: /tmp/ims-deployment-{{ target_env }}-{{ ansible_date_time.epoch }}.log

# tasks/deploy_ims_with_validation.yml
- name: Check circuit breaker status
  fail:
    msg: "Circuit breaker is OPEN. Deployment suspended to prevent cascading failures."
  when: circuit_open | default(false)

- name: Validate prerequisites
  block:
    - name: Check cluster connectivity
      redhat.openshift.k8s_info:
        api_version: v1
        kind: Node
      register: cluster_status
      failed_when: cluster_status.resources | length == 0

    - name: Validate namespace exists
      redhat.openshift.k8s_info:
        api_version: v1
        kind: Namespace
        name: "{{ ims_namespace }}"
      register: namespace_check
      failed_when: namespace_check.resources | length == 0

    - name: Check service account permissions
      redhat.openshift.k8s_info:
        api_version: v1
        kind: ServiceAccount
        name: "{{ ims_service_account }}"
        namespace: "{{ ims_namespace }}"
      register: sa_check
      failed_when: sa_check.resources | length == 0

- name: Deploy IMS resources with state validation
  redhat.openshift.k8s:
    state: present
    definition: "{{ lookup('template', 'ims-deployment.j2') | from_yaml }}"
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
    timeout: 10
  register: health_check
  retries: 10
  delay: 15
  until: health_check.status == 200

- name: Validate IMS connectivity
  uri:
    url: "http://{{ ims_service_name }}.{{ ims_namespace }}.svc.cluster.local:8080/ims/ping"
    method: GET
    status_code: 200
    timeout: 30
  register: ims_connectivity
  retries: 5
  delay: 10
  until: ims_connectivity.status == 200

- name: Reset circuit breaker on success
  set_fact:
    error_count: 0
    circuit_open: false
  when: deployment_result is succeeded and health_check.status == 200
```

**Validation Checkpoint**: Demonstrate failure recovery, circuit breaker activation, and successful deployment after transient failures.

### Exercise 3.3: Automated Testing with Molecule (10 minutes)
**Objective**: Create comprehensive test automation using Molecule framework for playbook validation

**Testing Strategy:**
- Unit tests for individual tasks
- Integration tests for complete workflows
- Infrastructure tests for OpenShift resources
- End-to-end tests for IMS connectivity

**Hands-on Tasks:**
1. Set up Molecule framework for OpenShift testing
2. Create test scenarios for different environments
3. Implement verification tests for deployed resources
4. Build continuous integration test pipeline

**Expected Deliverable:**
```yaml
# molecule/default/molecule.yml
dependency:
  name: galaxy
  options:
    requirements-file: collections/requirements.yml

driver:
  name: delegated
  options:
    managed: false
    ansible_connection_options:
      connection: local

platforms:
  - name: localhost
    groups:
      - k8s

provisioner:
  name: ansible
  inventory:
    group_vars:
      all:
        target_env: test
        ims_namespace: ims-molecule-test
        ims_service_name: ims-connector-test
  playbooks:
    converge: ../../../playbooks/idempotent_ocp.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - dependency
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - side_effect
    - verify
    - cleanup
    - destroy

# molecule/default/verify.yml
- name: Verify IMS deployment
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Check if namespace exists
      redhat.openshift.k8s_info:
        api_version: v1
        kind: Namespace
        name: "{{ ims_namespace }}"
      register: namespace_result
      failed_when: namespace_result.resources | length == 0

    - name: Verify deployment is available
      redhat.openshift.k8s_info:
        api_version: apps/v1
        kind: Deployment
        name: "{{ ims_service_name }}"
        namespace: "{{ ims_namespace }}"
      register: deployment_result
      failed_when: >
        deployment_result.resources | length == 0 or
        deployment_result.resources[0].status.availableReplicas != deployment_result.resources[0].status.replicas

    - name: Test service accessibility
      uri:
        url: "http://{{ ims_service_name }}.{{ ims_namespace }}.svc.cluster.local:8080/health"
        method: GET
        status_code: 200
      register: service_test

    - name: Verify RBAC configuration
      redhat.openshift.k8s_info:
        api_version: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        name: "{{ ims_service_account }}-binding"
      register: rbac_result
      failed_when: rbac_result.resources | length == 0

    - name: Test idempotency
      include_tasks: ../../../playbooks/idempotent_ocp.yml
      register: idempotent_run

    - name: Verify no changes on second run
      assert:
        that:
          - not idempotent_run.changed
        fail_msg: "Playbook is not idempotent - changes detected on second run"

# molecule/prod-simulation/molecule.yml (additional scenario)
dependency:
  name: galaxy

driver:
  name: delegated

platforms:
  - name: localhost

provisioner:
  name: ansible
  inventory:
    group_vars:
      all:
        target_env: prod
        ims_namespace: ims-prod-test
        persistent_storage_required: true
        security_config:
          prod_user_id: 1500
          prod_group_id: 1500

verifier:
  name: ansible
  playbooks:
    verify: verify.yml

scenario:
  test_sequence:
    - dependency
    - syntax
    - create
    - prepare
    - converge
    - side_effect
    - verify
    - cleanup
    - destroy
```

**Validation Checkpoint**: Run molecule tests successfully for both test and prod scenarios with full verification.

### Exercise 3.4: Troubleshooting Challenge (5 minutes)
**Objective**: Debug intentionally broken IMS deployment scenarios using systematic approaches

**Intentional Failure Scenarios:**
1. Service account permission failures
2. Network connectivity issues between IMS components
3. Resource quota limitations and optimization
4. Configuration template rendering errors

**Hands-on Tasks:**
1. Diagnose pre-staged deployment failures
2. Use systematic troubleshooting methodology
3. Implement fixes and verify resolution
4. Document lessons learned and prevention strategies

**Troubleshooting Scenarios:**

**Scenario A: Permission Denied Errors**
```yaml
# Broken configuration - deliberately missing RBAC
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ims-operator-broken
  namespace: ims-test
# Missing ClusterRoleBinding deliberately
```

**Scenario B: Resource Quota Exceeded**
```yaml
# Broken resource specification
resources:
  requests:
    memory: "16Gi"  # Exceeds quota deliberately
    cpu: "8000m"    # Exceeds quota deliberately
  limits:
    memory: "32Gi"
    cpu: "16000m"
```

**Scenario C: Network Policy Blocking**
```yaml
# Overly restrictive network policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ims-broken-network-policy
spec:
  podSelector:
    matchLabels:
      app: ims-connector
  policyTypes:
  - Ingress
  - Egress
  # No ingress or egress rules - blocks all traffic
```

**Expected Troubleshooting Process:**
```yaml
# troubleshooting/diagnostic_playbook.yml
- name: IMS Deployment Diagnostic
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Check cluster resource availability
      redhat.openshift.k8s_info:
        api_version: v1
        kind: ResourceQuota
        namespace: "{{ ims_namespace }}"
      register: quota_check

    - name: Verify service account permissions
      shell: |
        oc auth can-i create deployments --as=system:serviceaccount:{{ ims_namespace }}:{{ ims_service_account }}
      register: permission_check
      ignore_errors: true

    - name: Test network connectivity
      shell: |
        oc run network-test --image=busybox --rm -it --restart=Never -- nslookup {{ ims_service_name }}.{{ ims_namespace }}.svc.cluster.local
      register: network_test
      ignore_errors: true

    - name: Generate diagnostic report
      copy:
        content: |
          IMS Deployment Diagnostic Report
          Generated: {{ ansible_date_time.iso8601 }}
          
          Resource Quota Status:
          {{ quota_check.resources | to_nice_yaml }}
          
          Permission Check: {{ permission_check.stdout }}
          Network Test: {{ network_test.stdout }}
          
          Recommended Actions:
          {% if 'no' in permission_check.stdout %}
          - Fix RBAC permissions for service account
          {% endif %}
          {% if network_test.rc != 0 %}
          - Check network policies and service configuration  
          {% endif %}
        dest: "/tmp/ims-diagnostic-{{ ansible_date_time.epoch }}.txt"
```

## Technical Requirements

### Molecule Framework Setup
```bash
# Install molecule with OpenShift support
pip install molecule[ansible] molecule-plugins[docker]
pip install openshift kubernetes
```

### Testing Environment
- Dedicated test namespace per participant
- Pre-staged broken configurations for troubleshooting
- Monitoring and logging tools for diagnostic exercises

### Advanced Jinja2 Dependencies
```yaml
# requirements.txt for additional Jinja2 filters
jinja2-time>=0.2.0
jinja2-ansible-filters>=1.3.0
```

## Assessment Criteria

### Template Complexity
- [ ] Environment-specific resource generation
- [ ] Conditional logic based on cluster capabilities
- [ ] Complex data transformations implemented correctly
- [ ] Template readability and maintainability

### Error Handling Sophistication
- [ ] Retry logic with exponential backoff
- [ ] Circuit breaker pattern implementation
- [ ] State validation and repair mechanisms
- [ ] Comprehensive logging and alerting

### Testing Automation
- [ ] Molecule tests pass for all scenarios
- [ ] Idempotency validated automatically
- [ ] Integration tests verify end-to-end functionality
- [ ] Performance and load testing included

### Troubleshooting Skills
- [ ] Systematic diagnostic approach demonstrated
- [ ] Root cause identification within time limits
- [ ] Effective use of OpenShift diagnostic tools
- [ ] Knowledge transfer through documentation

## Progressive Skill Building

### Advanced Challenges
- Custom Jinja2 filter development
- Operator pattern implementation
- GitOps integration with advanced templating
- Multi-cluster deployment orchestration

### Knowledge Transfer Activities
- Peer code review sessions
- Troubleshooting knowledge sharing
- Best practices documentation creation
- Mentoring less experienced participants

## Workshop Completion Integration

**Final Validation:**
Participants deploy a complete IMS environment using all three modules:
1. Dynamic inventory discovers target clusters
2. Idempotent deployment with RBAC automation
3. Advanced templating with comprehensive error handling
4. Automated testing validates entire deployment

**Success Metrics:**
- Complete IMS environment deployed across dev/test/prod
- All Molecule tests passing
- Troubleshooting scenarios resolved independently
- Production-ready automation artifacts created

This final module synthesizes all workshop learning into production-ready automation capabilities suitable for enterprise IMS environments.