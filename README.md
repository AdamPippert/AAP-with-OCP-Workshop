# Advanced Ansible Automation Platform 2.5 with OpenShift Workshop

**Co-developed by Red Hat Telco and AI**

This repository contains a comprehensive 2.5-hour instructor-led workshop focused on advanced Ansible Automation Platform (AAP) 2.5 integration with OpenShift Container Platform for Information Management System (IMS) environment deployment patterns.

## Workshop Overview

### Target Audience
- System administrators and DevOps engineers
- Teams working on mainframe modernization projects
- Practitioners with basic AAP 2.5 knowledge (prerequisite: "Basic Deployment AAP 2.5" course)

### Learning Objectives
- Master advanced inventory management patterns for multi-cluster OpenShift environments
- Implement production-ready RBAC automation and idempotent resource deployment
- Develop sophisticated error handling and troubleshooting automation
- Deploy enterprise-scale IMS workloads using AAP and OpenShift integration

## Workshop Structure

### Module 1: Dynamic Inventory and AAP Integration (40 minutes)
**Focus:** Multi-cluster inventory management and event-driven synchronization
- Advanced inventory discovery patterns
- Cross-cluster application grouping
- Environment-based categorization
- Systematic troubleshooting approaches

### Module 2: Idempotent Resource Management and RBAC (45 minutes)
**Focus:** Production-ready deployment patterns with enterprise security
- Automated RBAC management with least-privilege principles
- Idempotent resource deployment using `redhat.openshift` collection
- Service account lifecycle management
- Security context constraints for IMS workloads

### Module 3: Advanced Automation and Error Handling (45 minutes)
**Focus:** Complex templating and systematic troubleshooting
- Advanced Jinja2 templating for environment-specific configurations
- Comprehensive error handling with retry mechanisms
- Molecule framework integration for automated testing
- Diagnostic automation and performance monitoring

## Repository Structure

```
AAP-with-OCP-Workshop/
├── docs/                           # Workshop guides and documentation
│   ├── module1-workshop-guide.md   # Module 1 exercise guide
│   ├── module2-workshop-guide.md   # Module 2 exercise guide
│   ├── module3-workshop-guide.md   # Module 3 exercise guide
│   ├── workshop-admin.md           # Administrator setup guide
│   └── html/                       # HTML versions of guides
├── playbooks/                      # Ansible playbooks (one per module)
│   ├── module1/                    # Dynamic inventory exercises
│   ├── module2/                    # RBAC and deployment exercises
│   └── module3/                    # Advanced automation exercises
├── roles/                          # Reusable Ansible roles
├── scripts/                        # Infrastructure automation scripts
│   ├── exercise0/                  # Workshop environment setup
│   ├── build-admin-page.sh         # Admin page generator
│   ├── deploy-admin-page.sh        # OpenShift deployment script
│   ├── setup_aap_resources.sh      # AAP resource management
│   └── build_execution_environment.sh # Custom EE builder
├── execution-environment/          # Custom execution environment definition
│   ├── execution-environment.yml   # ansible-builder configuration
│   ├── requirements.yml            # Ansible collections
│   ├── requirements.txt            # Python dependencies
│   └── bindep.txt                  # System packages
└── specs/                          # Workshop requirements and architecture
```

## Quick Start

### Prerequisites
- OpenShift cluster with admin access
- Ansible Automation Platform 2.5 access
- `oc` CLI configured and authenticated
- Bash shell environment (Linux/macOS/WSL)
- Ansible 2.5 Product Demo environment from Red Hat Demo Platform (accessible by RH or partners)
- details.txt file created from the "Users" section in the Demo Platform using the "Data" field

### Workshop Setup

1. **Clone Repository**
   ```bash
   git clone <repository-url>
   cd AAP-with-OCP-Workshop
   ```

2. **Configure Environment**
   ```bash
   # Ensure details.txt is populated by workshop moderator
   # Run complete workshop setup
   ./scripts/exercise0/setup_workshop.sh
   ```

3. **Generate Admin Resources**
   ```bash
   # Build admin access page
   ./scripts/build-admin-page.sh
   
   # Deploy to OpenShift cluster
   ./scripts/deploy-admin-page.sh
   ```

4. **Verify AAP Integration**
   ```bash
   # Check created resources
   ./scripts/setup_aap_resources.sh show
   ```

## Key Features

### Automated AAP Controller Integration
- **Project Creation**: Git-based project with workshop playbooks
- **Inventory Management**: OpenShift cluster inventory with workshop variables
- **Credential Management**: Bearer token credentials for cluster access
- **Job Templates**: 10 pre-configured templates covering all exercises
- **Execution Environment**: Custom EE with kubernetes.core collection

### Custom Execution Environment
Built with `ansible-builder` and includes:
- kubernetes.core and redhat.openshift collections
- Pre-installed OpenShift CLI tools (oc, kubectl)
- Python dependencies for Kubernetes/OpenShift integration
- Red Hat UBI8 base image for security compliance

### Professional Admin Interface
- HTML-based access page with lab credentials
- OpenShift route deployment with TLS termination
- Bearer token integration for seamless authentication
- Comprehensive resource management and cleanup

### Enterprise Security Features
- RBAC automation with least-privilege principles
- Service account lifecycle management
- Security context constraints for workloads
- Network policies for mainframe connectivity

## Administration

### Resource Management
```bash
# Create all AAP resources
./scripts/setup_aap_resources.sh setup

# Build execution environment only
./scripts/setup_aap_resources.sh build-ee

# Display created resources
./scripts/setup_aap_resources.sh show

# Clean up after workshop
./scripts/setup_aap_resources.sh cleanup
```

### Execution Environment Management
```bash
# Build with defaults
./scripts/build_execution_environment.sh

# Build and push to registry
./scripts/build_execution_environment.sh -r quay.io/myorg -p

# Force rebuild with custom tag
./scripts/build_execution_environment.sh -t workshop-v1.0 --force
```

### Maintenance Tasks

**Before Each Workshop:**
1. Update `details.txt` with current lab environment details
2. Run complete setup: `./scripts/exercise0/setup_workshop.sh`
3. Verify AAP resources: `./scripts/setup_aap_resources.sh show`
4. Test job template execution in AAP Controller
5. Deploy admin page: `./scripts/deploy-admin-page.sh`

**After Each Workshop:**
1. Clean up AAP resources: `./scripts/setup_aap_resources.sh cleanup`
2. Rotate all exposed credentials
3. Delete workshop namespaces and generated files
4. Archive workshop logs and feedback

## Technical Architecture

### Deployment Patterns
- **Environment Progression**: dev (4 CPU/8GB) → test (8 CPU/16GB) → prod (16 CPU/32GB)
- **Resource Quotas**: Configurable per environment with automatic scaling
- **Network Policies**: Mainframe connectivity patterns with security controls
- **Service Mesh**: Optional Istio integration for advanced traffic management

### Integration Points
- **AAP Controller**: REST API integration for resource lifecycle management
- **OpenShift**: Bearer token authentication with RBAC automation
- **Container Registry**: Support for private registries and image management
- **Git Repository**: Source control integration for playbook management

### Monitoring and Observability
- **Health Checks**: Automated validation for all workshop components
- **Logging**: Centralized log collection and analysis
- **Metrics**: Performance monitoring and resource utilization tracking
- **Alerting**: Proactive notification for workshop issues

## Troubleshooting

### Common Issues

**Build Failures:**
- Ensure container runtime (Docker/Podman) is available
- Verify access to registry.redhat.io for base images
- Check ansible-builder installation and version

**AAP Connectivity:**
- Verify AAP Controller URL and credentials in details.txt
- Test API connectivity: `curl -k ${AAP_URL}/api/v2/ping/`
- Check bearer token validity and permissions

**OpenShift Access:**
- Confirm bearer token authentication: `oc whoami`
- Verify cluster connectivity: `oc cluster-info`
- Check namespace permissions and resource quotas

### Support Resources
- Workshop guides: `docs/module*-workshop-guide.html`
- Architecture details: `specs/workshop_PRD.md`
- OpenShift documentation: https://docs.openshift.com/
- Ansible AAP documentation: https://docs.ansible.com/automation-controller/

## Contributing

This workshop is designed for enterprise deployment and follows strict quality standards:

- All code must pass linting and security validation
- Playbooks must be idempotent and safely re-executable
- Documentation must be comprehensive and maintained
- Changes require testing in multi-cluster environments

## License

This workshop content is provided under standard enterprise licensing terms. Please consult with Red Hat Telco regarding usage and distribution rights.

## Development Team

**Co-developed by Red Hat Telco and AI**

This workshop represents the collaborative effort between Red Hat's Telco engineering teams and advanced AI systems, combining deep industry expertise with automated development capabilities to deliver comprehensive training content for enterprise environments.

---

*Advanced Ansible Automation Platform 2.5 with OpenShift Workshop - Production-ready automation training for enterprise scale deployments.*
