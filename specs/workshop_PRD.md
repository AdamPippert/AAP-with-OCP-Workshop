# Advanced Ansible Automation Platform 2.5 Workshop: Product Requirements Document

## Executive Summary

This Product Requirements Document outlines the design for a **2.5-hour advanced instructor-led workshop** targeting professionals learning both OpenShift and Ansible for IMS (Information Management System) environment deployment. The workshop builds upon Red Hat's foundational "Basic Deployment AAP 2.5" course to provide hands-on experience with advanced integration patterns, automation techniques, and production-ready deployment strategies.

## Workshop Overview

### Target Audience
- **Primary**: System administrators and DevOps engineers with basic Ansible and OpenShift knowledge
- **Secondary**: Application architects involved in mainframe modernization projects  
- **Mixed Skill Levels**: Designed to accommodate participants with varying experience levels in both technologies simultaneously

### Learning Prerequisites
Based on the Red Hat Quick Course foundation, participants must have:
- Linux system administration experience
- Basic Ansible playbook development skills
- OpenShift Container Platform fundamentals
- Access to dedicated OpenShift cluster environment
- Completed "Basic Deployment AAP 2.5" course or equivalent knowledge

### Core Learning Objectives
Participants will gain practical skills to:
1. Implement dynamic inventory management for multi-cluster OpenShift environments
2. Integrate AAP 2.5 with OpenShift using production-ready patterns
3. Ensure idempotent resource management with proper error handling
4. Configure comprehensive RBAC automation for enterprise security
5. Apply advanced Jinja2 templating for complex deployment scenarios
6. Troubleshoot and validate IMS environment deployments effectively

## Technical Architecture Requirements

### Lab Environment Specifications
- **Individual Cluster Access**: Each participant requires dedicated OpenShift cluster access
- **Minimum Cluster Resources**: 32 GB RAM, 8 vCPU cores, 200 GB SSD storage per cluster
- **AAP 2.5 Integration**: Pre-installed Ansible Automation Platform Operator
- **Network Configuration**: Outbound connectivity for collections and content downloads
- **Service Account Setup**: Pre-configured service accounts with appropriate RBAC permissions

### Infrastructure Prerequisites
- **Container Registry Access**: Red Hat Registry authentication for official images
- **Persistent Storage**: Fast SSD storage class for database and application data
- **Network Policies**: Configured ingress/egress rules for IMS connectivity patterns
- **Backup Environment**: Cluster reset capability for troubleshooting scenarios

## Workshop Structure and Timing

### Module 1: Dynamic Inventory and AAP Integration (40 minutes)
**Time Allocation**: 10 min theory, 25 min hands-on, 5 min validation

**Learning Focus**: Advanced inventory management patterns for multi-cluster environments

**Hands-on Activities**:
- Configure constructed inventories combining multiple OpenShift clusters
- Implement OpenShift service discovery using kubernetes.core collection
- Set up automated inventory synchronization with API webhooks
- Troubleshoot common inventory sync failures and timeout issues

**Validation Checkpoint**: Successfully query hosts across three different cluster environments with dynamic grouping by namespace and resource type.

**Progressive Skill Building**: Start with single-cluster inventory, advance to multi-cluster patterns, culminate with event-driven inventory updates.

### Module 2: Idempotent Resource Management and RBAC (45 minutes)
**Time Allocation**: 15 min guided practice, 25 min independent exercise, 5 min peer review

**Learning Focus**: Production-ready resource management with comprehensive security

**Hands-on Activities**:
- Implement idempotent deployment patterns using redhat.openshift collection
- Create automated service account provisioning with RBAC binding
- Build rollback capabilities using block-rescue-always patterns
- Configure security context constraints for IMS workloads

**Validation Checkpoint**: Deploy, modify, and rollback an IMS connector service while maintaining proper security contexts and demonstrating true idempotency.

**IMS-Specific Scenarios**: 
- Mainframe connectivity service deployment
- Database connection pooling configuration  
- Legacy system integration patterns

### Module 3: Advanced Automation and Error Handling (45 minutes)
**Time Allocation**: 5 min concept review, 30 min collaborative exercise, 10 min troubleshooting challenge

**Learning Focus**: Complex templating, error handling, and production troubleshooting

**Hands-on Activities**:
- Build complex Jinja2 templates for environment-specific OpenShift configurations
- Implement comprehensive error handling with retry mechanisms and state validation
- Create automated testing pipelines using Molecule framework
- Debug intentionally broken IMS deployment scenarios

**Validation Checkpoint**: Successfully deploy a complex IMS environment with proper error handling, recover from simulated failures, and validate deployment through automated tests.

**Troubleshooting Scenarios**:
- Service account permission failures
- Network connectivity issues between IMS components
- Resource quota limitations and optimization

### Wrap-up and Action Planning (15 minutes)
- Key concepts summary and real-world application discussion
- Individual action planning for implementing learned techniques
- Resource sharing and follow-up learning paths
- Feedback collection and workshop evaluation

## Progressive Skill Building Framework

### Scaffolding Approach
**Foundation Building**: Each module begins with guided demonstrations building on AAP 2.5 architectural concepts from the prerequisite course.

**Graduated Complexity**: 
1. **Basic Operations**: Single-resource management with standard modules
2. **Integration Patterns**: Multi-resource workflows with dependencies
3. **Production Scenarios**: Complete IMS environment deployment with monitoring

**Support Structure**:
- **Peer Pairing**: Advanced participants mentor those with less OpenShift experience
- **Flexible Pacing**: Optional advanced exercises for fast finishers
- **Individual Coaching**: Instructor provides targeted support during hands-on activities

### Skill Validation Strategy
**Continuous Assessment**: 
- **Real-time Observation**: Instructor monitors practical exercise completion
- **Peer Code Review**: Participants evaluate each other's playbook implementations  
- **Problem-solving Challenges**: Intentional failures requiring diagnostic skills

**Competency Thresholds**:
- **Module 1**: Successfully manage inventory across multiple clusters
- **Module 2**: Deploy and modify resources with proven idempotency
- **Module 3**: Recover from failures and validate deployment integrity

## Practical Exercise Design

### IMS Environment Simulation
**Realistic Use Cases**:
- **Legacy Integration**: Connect containerized applications to mainframe IMS databases
- **Multi-environment Deployment**: Promote applications through dev/test/prod pipelines
- **Disaster Recovery**: Implement backup and restore procedures for critical services

**Production-Ready Patterns**:
- **Blue-Green Deployments**: Zero-downtime updates for IMS services
- **Canary Releases**: Gradual traffic shifting with automated rollback
- **High Availability**: Multi-replica deployments with proper load balancing

### Cluster Preparation Automation
**Pre-workshop Setup Scripts**:
```bash
# Operator installation automation
oc apply -f aap-operator-subscription.yaml
oc wait --for=condition=Established crd/automationcontrollers.automationcontroller.ansible.com

# Namespace and RBAC preparation
for env in dev test prod; do
  oc create namespace ims-${env}
  oc create serviceaccount ims-operator -n ims-${env}
  oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:ims-${env}:ims-operator
done
```

**Resource Quota Configuration**:
- **Development**: 4 CPU, 8 GB RAM, 50 GB storage
- **Testing**: 8 CPU, 16 GB RAM, 100 GB storage  
- **Production**: 16 CPU, 32 GB RAM, 200 GB storage

## Assessment and Evaluation Framework

### Performance-Based Assessment
**Practical Demonstrations**:
- **Live Deployment**: Complete IMS service deployment under observation
- **Troubleshooting Challenge**: Diagnose and resolve pre-staged failures
- **Integration Test**: Validate end-to-end connectivity and functionality

**Assessment Rubric**:
- **Functional**: Does the solution work as intended?
- **Idempotent**: Can it be safely re-executed multiple times?
- **Secure**: Are proper RBAC and security contexts implemented?
- **Maintainable**: Is the code readable and properly documented?

### Troubleshooting Validation
**Scenario-Based Challenges**:
1. **Authentication Failure**: Service account token expiration
2. **Resource Constraints**: Memory limits causing pod failures  
3. **Network Issues**: Service discovery and ingress problems
4. **Data Persistence**: Volume mounting and permission errors

**Expected Response Pattern**:
- **Systematic Diagnosis**: Logical troubleshooting approach
- **Tool Usage**: Proper use of oc logs, oc describe, and Ansible debugging
- **Documentation**: Clear explanation of problem and solution
- **Knowledge Transfer**: Ability to explain issue to teammates

## Instructor Delivery Guidelines

### Facilitation Strategies
**Mixed Skill Level Management**:
- **Tiered Exercises**: Basic, intermediate, and advanced versions of each activity
- **Peer Mentoring**: Structured pairing of experienced with novice participants
- **Individual Support**: One-on-one coaching during complex exercises
- **Extension Activities**: Additional challenges for advanced participants

**Real-time Adaptation**:
- **Pace Monitoring**: Regular check-ins on exercise completion rates
- **Content Flexibility**: Ability to compress or expand modules based on group progress
- **Support Escalation**: Clear process for handling technical difficulties

### Technical Preparation Requirements
**Instructor Qualifications**:
- **Dual Expertise**: Deep knowledge of both Ansible Automation Platform and OpenShift
- **IMS Experience**: Understanding of mainframe integration patterns
- **Workshop Facilitation**: Experience managing hands-on technical training

**Pre-workshop Setup**:
- **Environment Validation**: Test all exercises in identical cluster environments
- **Troubleshooting Database**: Document common issues and solutions
- **Backup Plans**: Alternative exercises for system failures

## Success Metrics and Outcomes

### Immediate Learning Outcomes
**Technical Skills Demonstrated**:
- **100% of participants** successfully deploy multi-environment IMS services
- **90% of participants** demonstrate proper error handling and rollback procedures
- **85% of participants** complete advanced troubleshooting scenarios independently

**Knowledge Transfer Validation**:
- **Peer Teaching**: Participants explain concepts to fellow attendees
- **Documentation Creation**: Produce reusable playbooks and procedures
- **Problem-solving Confidence**: Successfully handle unexpected technical challenges

### Long-term Impact Measures
**Organizational Benefits**:
- **Reduced Deployment Time**: Automated processes replace manual procedures
- **Improved Reliability**: Idempotent operations reduce configuration drift
- **Enhanced Security**: Systematic RBAC implementation across environments
- **Knowledge Scaling**: Participants train additional team members

**Professional Development**:
- **Certification Preparation**: Skills align with Red Hat Certified Specialist paths
- **Career Advancement**: Practical automation expertise for modern infrastructure roles
- **Technical Leadership**: Ability to guide automation adoption in enterprise environments

## Resource Requirements and Dependencies

### Educational Materials
**Pre-workshop Preparation**:
- **Setup Guide**: Detailed environment configuration instructions
- **Reference Architecture**: IMS deployment patterns and best practices
- **Troubleshooting Playbook**: Common issues and resolution procedures

**Workshop Resources**:
- **Hands-on Lab Guide**: Step-by-step exercise instructions with code examples
- **Template Library**: Reusable Jinja2 templates for common scenarios
- **Validation Scripts**: Automated testing tools for exercise verification

### Technical Dependencies
**Software Requirements**:
- **OpenShift Container Platform 4.12+** with administrative access
- **Ansible Automation Platform 2.5** with proper licensing
- **Red Hat Registry Access** for official container images
- **Git Repository Access** for playbook version control

**Infrastructure Dependencies**:
- **Dedicated Clusters**: One OpenShift cluster per participant
- **Network Connectivity**: Reliable internet access for content downloads
- **Persistent Storage**: High-performance storage for database workloads
- **Backup Procedures**: Cluster reset capability for exercise recovery

This comprehensive workshop design provides practical, production-ready skills for IMS environment deployment while accommodating mixed skill levels through progressive learning techniques and extensive hands-on practice. The 2.5-hour format optimizes learning retention while providing sufficient depth for real-world application.