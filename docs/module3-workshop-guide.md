# Module 3: Advanced Automation and Error Handling - Workshop Guide

## Overview

**Duration:** 45 minutes  
**Objective:** Master complex Jinja2 templating, comprehensive error handling patterns, automated testing with Molecule framework, and advanced troubleshooting techniques for production IMS environments

In this final module, you'll synthesize all workshop learning into enterprise-grade automation capabilities, implementing sophisticated templating, circuit breaker patterns, automated testing pipelines, and systematic troubleshooting methodologies.

## Prerequisites

Before starting this module, ensure you have:

- [ ] Completed Modules 1 and 2 with working deployments
- [ ] Understanding of Jinja2 templating concepts
- [ ] Molecule framework installed (`pip install molecule[ansible]`)
- [ ] Working IMS deployment from Module 2
- [ ] Access to multiple environment configurations (dev/test/prod)

### Quick Environment Check

```bash
# Verify Molecule installation
molecule --version

# Check existing IMS deployment from Module 2
oc get deployment -n ims-dev ims-connector -o wide

# Verify template rendering capability
ansible localhost -m template -a "src=templates/test.j2 dest=/tmp/test.yml" --check

# Test advanced Jinja2 filters
pip list | grep -i jinja2
```

## Module Structure

| Exercise | Duration | Focus Area |
|----------|----------|------------|
| 3.1 | 15 min | Advanced Jinja2 Templating |
| 3.2 | 15 min | Comprehensive Error Handling and Retry Logic |
| 3.3 | 10 min | Automated Testing with Molecule |
| 3.4 | 5 min | Troubleshooting Challenge |

---

## Exercise 3.1: Advanced Jinja2 Templating

**⏱️ Time Allocation:** 15 minutes (10 min implementation, 5 min testing)

### Learning Objectives
- Create dynamic, environment-aware OpenShift resource definitions
- Implement conditional resource generation based on cluster capabilities
- Build complex data transformations for IMS connectivity patterns

### Step-by-Step Instructions

#### Step 1: Review Advanced Template Structure (3 minutes)

```bash
# Examine the advanced templating playbook
cat playbooks/module3/exercise3-1-advanced-templating.yml

# Review the complex template structure
cat roles/ims_deployment/templates/application.yml.j2

# Check environment-specific configuration
cat group_vars/all/environment_config.yml
```

**Key Templating Concepts:**
- **Conditional Blocks** - `{% if target_env == 'prod' %}` for environment-specific logic
- **Complex Loops** - `{% for key, value in pod_annotations.items() %}` for dynamic data
- **Data Transformations** - Environment-specific resource calculations
- **Nested Variables** - `{{ environment_config[target_env].replicas }}` for structured data

#### Step 2: Generate Environment-Specific Configurations (7 minutes)

```bash
# Generate development environment configuration
ansible-playbook playbooks/module3/exercise3-1-advanced-templating.yml \
  -e target_env=dev \
  -e debug_templating=true

# Generate production environment configuration
ansible-playbook playbooks/module3/exercise3-1-advanced-templating.yml \
  -e target_env=prod \
  -e debug_templating=true

# Compare generated configurations
diff /tmp/ims-config-dev.yml /tmp/ims-config-prod.yml
```

#### Step 3: Test Template Conditional Logic (5 minutes)

```bash
# Test template with different variables
ansible-playbook playbooks/module3/exercise3-1-advanced-templating.yml \
  -e target_env=prod \
  -e persistent_storage_required=true \
  -e enable_monitoring=true

# Verify conditional resources were generated
grep -A 10 "volumes:" /tmp/ims-config-prod.yml
grep -A 5 "affinity:" /tmp/ims-config-prod.yml

# Test template error handling
ansible-playbook playbooks/module3/exercise3-1-advanced-templating.yml \
  -e target_env=invalid_env
```

#### Step 4: Validation Checkpoint (5 minutes)

**Expected Results:**
- ✅ Development config has minimal resources and no affinity rules
- ✅ Production config includes persistent storage, anti-affinity, and monitoring
- ✅ Environment-specific resource limits are applied correctly
- ✅ Template validation catches invalid environment configurations

**Troubleshooting Template Issues:**

| Issue | Symptoms | Solution |
|-------|----------|----------|
| Template syntax error | "TemplateSyntaxError" | Check Jinja2 syntax: brackets, quotes, filters |
| Undefined variable | "UndefinedError" | Add variable defaults: `{{ var \| default('value') }}` |
| Wrong conditional logic | Resources in wrong environment | Review `{% if %}` conditions and variable values |

---

## Exercise 3.2: Comprehensive Error Handling and Retry Logic

**⏱️ Time Allocation:** 15 minutes (10 min implementation, 5 min testing)

### Learning Objectives
- Implement exponential backoff retry mechanisms
- Create circuit breaker patterns for external dependencies
- Build state validation and repair automation
- Develop comprehensive logging and alerting capabilities

### Step-by-Step Instructions

#### Step 1: Review Advanced Error Handling Patterns (3 minutes)

```bash
# Examine the error handling playbook
cat playbooks/module3/exercise3-2-error-handling.yml

# Review the retry logic implementation
grep -A 15 "exponential backoff" playbooks/module3/exercise3-2-error-handling.yml

# Check circuit breaker configuration
grep -A 10 "circuit_breaker" playbooks/module3/exercise3-2-error-handling.yml
```

**Advanced Error Handling Components:**
- **Exponential Backoff** - `delay: {{ [base_delay * (2 ** retry_attempt), max_delay] | min }}`
- **Circuit Breaker** - Prevents cascade failures when services are unavailable
- **State Validation** - Comprehensive health checks before marking success
- **Comprehensive Logging** - Detailed error tracking and alerting

#### Step 2: Test Successful Deployment with Advanced Error Handling (4 minutes)

```bash
# Run deployment with comprehensive error handling
ansible-playbook playbooks/module3/exercise3-2-error-handling.yml \
  -e target_env=dev \
  -e ims_version=1.3.0

# Check detailed deployment logs
cat /tmp/ims-deployment-dev-$(date +%Y%m%d).log

# Verify circuit breaker status
grep -i "circuit.*closed" /tmp/ims-deployment-dev-$(date +%Y%m%d).log
```

#### Step 3: Simulate Failure Scenarios and Recovery (5 minutes)

```bash
# Test exponential backoff with temporary failures
ansible-playbook playbooks/module3/exercise3-2-error-handling.yml \
  -e target_env=dev \
  -e simulate_transient_failure=true \
  -e max_retries=3

# Test circuit breaker activation
ansible-playbook playbooks/module3/exercise3-2-error-handling.yml \
  -e target_env=dev \
  -e simulate_circuit_breaker=true \
  -e circuit_breaker_threshold=2

# Verify recovery after circuit breaker reset
sleep 30
ansible-playbook playbooks/module3/exercise3-2-error-handling.yml \
  -e target_env=dev \
  -e ims_version=1.3.1
```

#### Step 4: Test State Validation and Repair (3 minutes)

```bash
# Introduce configuration drift
oc scale deployment ims-connector --replicas=1 -n ims-dev

# Run playbook to detect and repair drift
ansible-playbook playbooks/module3/exercise3-2-error-handling.yml \
  -e target_env=dev \
  -e enable_drift_detection=true

# Verify repair was successful
oc get deployment ims-connector -n ims-dev -o jsonpath='{.spec.replicas}'
```

**Expected Behavior:**
- ✅ Exponential backoff increases delay between retry attempts
- ✅ Circuit breaker opens after threshold failures and prevents further attempts
- ✅ State validation detects configuration drift and repairs automatically
- ✅ Comprehensive logging captures all error scenarios and recovery actions

---

## Exercise 3.3: Automated Testing with Molecule

**⏱️ Time Allocation:** 10 minutes (6 min setup, 4 min execution)

### Learning Objectives
- Create comprehensive test automation using Molecule framework
- Implement test scenarios for different environments
- Build verification tests for deployed resources
- Validate idempotency and integration testing

### Step-by-Step Instructions

#### Step 1: Review Molecule Test Structure (2 minutes)

```bash
# Examine the Molecule configuration
cat molecule/default/molecule.yml

# Review test scenarios
ls -la molecule/
cat molecule/default/verify.yml
```

#### Step 2: Execute Molecule Test Suite (4 minutes)

```bash
# Run the default test scenario
cd /Users/apippert/Development/AAP-with-OCP-Workshop
molecule test

# Run specific test scenario for production simulation
molecule test -s prod-simulation
```

#### Step 3: Analyze Test Results and Coverage (4 minutes)

```bash
# Review test execution logs
molecule test --debug | tail -50

# Check idempotency test results
grep -i "idempotent" molecule/default/molecule.log

# Verify all test assertions passed
grep -i "TASK.*assert" molecule/default/molecule.log
```

**Expected Test Coverage:**
- ✅ Syntax validation passes for all playbooks
- ✅ Deployment converges successfully
- ✅ Idempotency test shows no changes on second run
- ✅ All resource verification assertions pass
- ✅ Service health checks validate connectivity

---

## Exercise 3.4: Troubleshooting Challenge

**⏱️ Time Allocation:** 5 minutes

### Learning Objectives
- Debug intentionally broken IMS deployment scenarios
- Use systematic troubleshooting methodology
- Apply diagnostic tools and techniques learned throughout workshop

### Step-by-Step Instructions

#### Step 1: Diagnose Pre-Staged Failures (3 minutes)

```bash
# Run the troubleshooting challenge playbook
ansible-playbook playbooks/module3/exercise3-4-troubleshooting.yml \
  -e deploy_broken_scenario=permission_denied

# Use systematic diagnostic approach
ansible-playbook troubleshooting/diagnostic_playbook.yml \
  -e target_env=dev

# Review diagnostic report
cat /tmp/ims-diagnostic-$(date +%s).txt
```

#### Step 2: Implement Fixes and Verify Resolution (2 minutes)

```bash
# Apply systematic fixes based on diagnostic results
ansible-playbook playbooks/module3/exercise3-3-troubleshooting.yml \
  -e fix_discovered_issues=true

# Validate resolution
oc get deployment ims-connector -n ims-dev -o wide
curl -s http://ims-connector.ims-dev.svc.cluster.local:8080/health
```

**Troubleshooting Scenarios Covered:**
- **Scenario A:** Service account permission failures
- **Scenario B:** Resource quota exceeded errors
- **Scenario C:** Network policy blocking connectivity
- **Scenario D:** Template rendering errors

**Expected Diagnostic Process:**
1. **Systematic Information Gathering** - Collect logs, resource states, permissions
2. **Root Cause Analysis** - Identify the underlying issue from symptoms
3. **Fix Implementation** - Apply appropriate corrections
4. **Validation** - Confirm resolution and prevent recurrence

---

## Module 3 Validation Checkpoints

Complete these validation steps to confirm your mastery:

### ✅ Checkpoint 1: Advanced Templating
```bash
# This should generate different configurations for each environment
ansible-playbook playbooks/module3/exercise3-1-advanced-templating.yml -e target_env=dev
ansible-playbook playbooks/module3/exercise3-1-advanced-templating.yml -e target_env=prod
diff /tmp/ims-config-dev.yml /tmp/ims-config-prod.yml | wc -l
```

### ✅ Checkpoint 2: Error Handling Sophistication
```bash
# This should show retry attempts and successful recovery
grep -c "Retry attempt" /tmp/ims-deployment-dev-$(date +%Y%m%d).log
```

### ✅ Checkpoint 3: Automated Testing
```bash
# This should show all tests passing
molecule test --dry-run | grep -c "PLAY RECAP.*ok"
```

### ✅ Checkpoint 4: Troubleshooting Skills
```bash
# This should show comprehensive diagnostic information
test -f /tmp/ims-diagnostic-*.txt && echo "Diagnostic report generated successfully"
```

## Workshop Final Integration Challenge

### Complete IMS Environment Deployment

Deploy a production-ready IMS environment using all three modules:

```bash
# Step 1: Use Module 1 dynamic inventory to discover targets
ansible-inventory -i inventory/exercise1-2-multi-cluster.yml --list

# Step 2: Deploy with Module 2 idempotent patterns and RBAC
ansible-playbook playbooks/module2/exercise2-1-idempotent-deployment.yml \
  -e target_env=prod

# Step 3: Apply Module 3 advanced templating and error handling
ansible-playbook playbooks/module3/exercise3-2-error-handling.yml \
  -e target_env=prod \
  -e enable_production_monitoring=true

# Step 4: Validate with automated testing
molecule test -s prod-simulation
```

**Success Criteria:**
- [ ] Multi-cluster inventory discovers all target environments
- [ ] Idempotent deployment with comprehensive RBAC automation
- [ ] Advanced templating generates environment-appropriate configurations
- [ ] Error handling provides resilient deployment patterns
- [ ] Automated testing validates entire workflow
- [ ] Troubleshooting skills demonstrate systematic problem resolution

## Common Issues and Solutions

### Issue 1: "Template rendering failed"
**Symptoms:** Jinja2 template errors or undefined variables
**Diagnosis:**
```bash
ansible-playbook <playbook> --syntax-check
ansible-playbook <playbook> -e debug_templating=true --check
```
**Solution:** Verify template syntax and ensure all variables are defined with defaults

### Issue 2: "Molecule test failures"
**Symptoms:** Test assertions fail or resources not properly validated
**Diagnosis:**
```bash
molecule test --debug
molecule verify --debug
```
**Solution:** Check test expectations against actual resource states, update verification tasks

### Issue 3: "Circuit breaker stuck open"
**Symptoms:** Deployments fail immediately without retry attempts
**Solution:**
- Check circuit breaker timeout configuration
- Manually reset circuit breaker state: `-e reset_circuit_breaker=true`
- Verify underlying service availability

### Issue 4: "Exponential backoff not working"
**Symptoms:** Retries occur too quickly or don't increase delay properly
**Solution:**
- Verify mathematical expression in delay calculation
- Check `max_delay` and `base_delay` variable values
- Review retry loop implementation

## Module 3 Completion Checklist

Workshop completion requires mastery of:

- [ ] Complex Jinja2 templating with conditional logic and data transformations
- [ ] Production-grade error handling with retry mechanisms and circuit breakers
- [ ] Automated testing pipelines using Molecule framework
- [ ] Systematic troubleshooting methodology for production environments
- [ ] Integration of all three modules into cohesive automation workflow
- [ ] Documentation of lessons learned and best practices

## Knowledge Transfer and Continuous Learning

### Advanced Challenges for Continued Development
- [ ] Custom Jinja2 filter development for specialized transformations
- [ ] Operator pattern implementation using operator-sdk
- [ ] GitOps integration with ArgoCD for declarative deployments
- [ ] Multi-cluster deployment orchestration across regions

### Best Practices Documentation
Create documentation covering:
- [ ] Template library for common IMS patterns
- [ ] Error handling playbook collection
- [ ] Troubleshooting runbook for production incidents
- [ ] Testing strategy guide for complex automation

## Workshop Success Metrics

**Individual Mastery:**
- Complete IMS environment deployed across dev/test/prod
- All Molecule tests passing consistently
- Troubleshooting scenarios resolved independently within time limits
- Production-ready automation artifacts suitable for enterprise use

**Knowledge Transfer:**
- Peer code review participation and constructive feedback
- Documentation of lessons learned and prevention strategies
- Mentoring support for less experienced participants
- Best practices sharing with broader team

## Additional Resources

### Production Implementation Guide
```bash
# Recommended directory structure for production use
enterprise-ims-automation/
├── inventories/
│   ├── production/
│   ├── staging/
│   └── development/
├── playbooks/
│   ├── site.yml
│   ├── deploy-ims.yml
│   └── troubleshoot.yml
├── roles/
│   ├── ims_deployment/
│   ├── ims_rbac/
│   └── ims_monitoring/
├── molecule/
│   ├── default/
│   └── production/
└── docs/
    ├── runbooks/
    └── architecture/
```

### Enterprise Integration Patterns
- **CI/CD Integration:** Jenkins/GitLab pipelines with Molecule testing
- **Monitoring Integration:** Prometheus metrics and Grafana dashboards
- **Security Integration:** Vault secrets management and compliance scanning
- **Documentation Integration:** Automated documentation generation from templates

---

**🎉 Workshop Complete!** You now possess enterprise-grade automation capabilities for IMS environments, combining dynamic inventory management, idempotent deployments, advanced templating, comprehensive error handling, and systematic troubleshooting skills. These patterns are production-ready and suitable for complex enterprise mainframe modernization initiatives.