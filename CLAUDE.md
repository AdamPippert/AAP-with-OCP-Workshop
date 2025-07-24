# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **Advanced Ansible Automation Platform (AAP) 2.5 Workshop** repository designed for a 2.5-hour instructor-led training session. The workshop focuses on OpenShift Container Platform integration with AAP for IMS (Information Management System) environment deployment patterns.

**Key Technologies:**
- Ansible Automation Platform 2.5
- OpenShift Container Platform 4.12+
- Red Hat Collections (`kubernetes.core`, `redhat.openshift`)
- Bash scripting for infrastructure automation

## Repository Structure

The repository follows a workshop-oriented structure with three main learning modules:

```
scripts/           # Infrastructure automation scripts
playbooks/         # Ansible playbooks (one per module)
roles/            # Reusable Ansible roles
specs/            # Workshop requirements and documentation
ai_docs/          # Generated documentation (git-ignored)
.agents/          # Custom agent commands (git-ignored)
```

**Key Files:**
- `generate_scaffold_fixed.sh` - Repository scaffolding automation
- `specs/workshop_PRD.md` - Comprehensive workshop requirements
- `specs/structure.md` - Planned directory structure

## Development Commands

Since this is a workshop repository in early development phase, standard commands are:

**Repository Setup:**
```bash
./generate_scaffold_fixed.sh scaffold.txt
```

**Expected Future Commands:**
```bash
# Ansible playbook execution
ansible-playbook playbooks/<playbook>.yml

# OpenShift resource management
oc apply -f <resources>

# Infrastructure scripts
./scripts/01_install_aap_operator.sh
./scripts/02_deploy_showroom.sh
./scripts/99_cleanup.sh
```

## Workshop Architecture

**Three Learning Modules:**
1. **Dynamic Inventory and AAP Integration** (40 min) - Multi-cluster inventory management
2. **Idempotent Resource Management and RBAC** (45 min) - Production-ready deployment patterns
3. **Advanced Automation and Error Handling** (45 min) - Complex templating and troubleshooting

**Key Learning Patterns:**
- Progressive skill building from basic to production-ready scenarios
- Idempotent resource management using `redhat.openshift` collection
- Advanced Jinja2 templating for environment-specific configurations
- Comprehensive error handling with retry mechanisms
- RBAC automation for enterprise security patterns

## Development Guidelines

**Ansible Best Practices:**
- All playbooks must be idempotent and safely re-executable
- Use proper error handling with `block-rescue-always` patterns
- Implement dynamic inventory management for multi-cluster environments
- Follow Red Hat collection standards for OpenShift integration

**Workshop Design Principles:**
- Hands-on activities with validation checkpoints
- Support mixed skill levels through tiered exercises
- Production-ready patterns for IMS environment deployment
- Systematic troubleshooting approaches with proper tooling

**File Naming Conventions:**
- Scripts: `##_descriptive_name.sh` (numbered execution order)
- Playbooks: `descriptive_name.yml` (one per workshop module)
- Documentation: `kebab-case.md` in `specs/` directory

## Testing and Validation

**Expected Testing Framework:**
- Molecule framework for automated playbook testing
- Validation scripts for exercise verification
- OpenShift cluster-based integration testing

**Environment Requirements:**
- Dedicated OpenShift cluster per participant
- Service accounts with cluster-admin RBAC permissions
- Resource quotas: dev (4 CPU/8GB), test (8 CPU/16GB), prod (16 CPU/32GB)

## Security Considerations

- Service account tokens and cluster credentials in `.env` (git-ignored)
- RBAC automation with least-privilege principles
- Security context constraints for IMS workloads
- Network policies for mainframe connectivity patterns

## Workshop Delivery Context

This repository supports instructor-led training targeting system administrators and DevOps engineers working on mainframe modernization projects. The content builds upon Red Hat's "Basic Deployment AAP 2.5" prerequisite course and emphasizes practical, production-ready automation skills for enterprise environments.