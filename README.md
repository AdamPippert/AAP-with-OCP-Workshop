# Advanced Ansible Automation Platform 2.5 with OpenShift Workshop

**Co-developed by Red Hat Telco and AI**

This repository contains a comprehensive workshop delivery system for the Advanced Ansible Automation Platform (AAP) 2.5 integration with OpenShift Container Platform. The workshop includes automated multi-user setup, browser-based VSCode development environments, and automated email notifications for participants.

## 🎯 Workshop Overview

### Target Audience
- System administrators and DevOps engineers working on mainframe modernization
- Teams implementing AAP and OpenShift integration patterns
- Practitioners with basic AAP 2.5 knowledge (prerequisite: "Basic Deployment AAP 2.5" course)

### Workshop Modules
- **Module 1:** Dynamic Inventory and AAP Integration (40 minutes)
- **Module 2:** Idempotent Resource Management and RBAC (45 minutes)  
- **Module 3:** Advanced Automation and Error Handling (45 minutes)

### Key Features
- 🖥️ **Browser-based VSCode environments** for each participant
- 🤖 **Automated AAP Controller setup** with job templates and credentials
- ☸️ **OpenShift integration** with RBAC and resource management
- 📧 **Automated email notifications** with personalized access details
- 📊 **Multi-user management** supporting 50+ participants
- 🚀 **One-command deployment** for complete workshop setup

## 🚀 Quick Start for Workshop Delivery

### Prerequisites
- OpenShift cluster with admin access
- `oc` CLI configured and authenticated
- Workshop details from Red Hat Demo Platform (RHDP)
- Bash shell environment (Linux/macOS/WSL)

### Complete Workshop Setup

#### Step 1: Clone and Prepare Repository
```bash
git clone <repository-url>
cd AAP-with-OCP-Workshop
```

#### Step 2: Obtain Workshop Details
1. Request AAP Product Demo environments from RHDP (Red Hat Demo Platform)
2. For workshops with 30+ users, request multiple environments:
   - `workshop_details.txt` (users 1-30)
   - `workshop_details2.txt` (users 31-60)
   - Add more files as needed for larger workshops

3. Download the "bulk export" data from RHDP and save as `workshop_details.txt` in the repository root

#### Step 3: Parse Workshop Details
```bash
# Parse workshop details for all users
./scripts/parse_workshop_details.sh -v

# Review parsed users
cat user_environments/users.csv
cat user_environments/summary.txt
```

#### Step 4: Deploy Complete Workshop Infrastructure
```bash
# Deploy AAP environments, VSCode servers, and generate emails
./scripts/setup_multi_user.sh --vscode --generate-emails -p 10 -v

# This command will:
# - Set up AAP Controller for each user
# - Deploy VSCode development environments  
# - Create OpenShift routes and services
# - Generate personalized email notifications
# - Validate all environments
```

#### Step 5: Validate and Send Notifications
```bash
# Validate all environments are working
./scripts/validate_multi_user.sh --full

# Review generated emails
ls workshop_emails/
cat workshop_emails/DELIVERY_INSTRUCTIONS.md

# Send emails to participants (multiple options available)
# See "Email Delivery Options" section below
```

### 📧 Email Delivery Options

The system generates multiple formats for sending credentials to participants:

#### Option A: Gmail Mail Merge (Recommended)
```bash
# Use the generated CSV file
open workshop_emails/workshop_emails.csv

# Instructions:
# 1. Import CSV into Google Sheets
# 2. Install "Mail Merge" add-on
# 3. Create email template with merge fields
# 4. Send personalized emails to all users
```

#### Option B: Individual HTML Emails
```bash
# Use individual HTML files
open workshop_emails/html/

# For each user:
# 1. Open user##_email.html in browser
# 2. Copy the formatted content
# 3. Paste into your email client
# 4. Send to participant
```

#### Option C: Outlook Mail Merge
```bash
# Use CSV with Outlook's built-in mail merge
# 1. Mailings → Start Mail Merge → E-mail Messages
# 2. Select Recipients → Use Existing List
# 3. Choose workshop_emails/workshop_emails.csv
# 4. Create template and complete merge
```

## 📊 Workshop Management Commands

### Multi-User Operations
```bash
# Setup specific user range
./scripts/setup_multi_user.sh -u 1-10 --vscode

# Resume failed setups
./scripts/setup_multi_user.sh --resume

# Force re-setup specific users
./scripts/setup_multi_user.sh -u 5,8,12 --force

# High-parallel setup for large workshops
./scripts/setup_multi_user.sh -p 15 --vscode --generate-emails
```

### VSCode Environment Management
```bash
# Check deployment status
./scripts/manage_vscode.sh status

# Get user access URLs
./scripts/manage_vscode.sh url
./scripts/manage_vscode.sh url -u 1-10

# Restart VSCode instances
./scripts/manage_vscode.sh restart -u 5

# View logs for troubleshooting
./scripts/manage_vscode.sh logs -u 3

# Remove VSCode instances
./scripts/manage_vscode.sh undeploy -u 1-5
```

### Environment Validation
```bash
# Quick connectivity check
./scripts/validate_multi_user.sh --quick

# Full validation with details
./scripts/validate_multi_user.sh --full -v

# Validate specific users
./scripts/validate_multi_user.sh -u 1-5 --full
```

### Email Management
```bash
# Generate all email formats
./scripts/generate_workshop_emails.sh

# Generate specific format
./scripts/generate_workshop_emails.sh --format csv

# Generate for specific users
./scripts/generate_workshop_emails.sh -u 1-10 --format html

# Customize email content
./scripts/generate_workshop_emails.sh \
  --exercises-url "https://your-workshop.com" \
  --instructor "instructor@redhat.com"
```

## 🏗️ Repository Structure

```
AAP-with-OCP-Workshop/
├── scripts/                          # Automation scripts
│   ├── parse_workshop_details.sh     # Parse RHDP bulk exports
│   ├── setup_multi_user.sh           # Multi-user workshop setup
│   ├── validate_multi_user.sh        # Environment validation
│   ├── deploy_vscode.sh               # VSCode server deployment
│   ├── manage_vscode.sh               # VSCode management
│   ├── generate_workshop_emails.sh    # Email generation
│   └── exercise0/setup_workshop.sh    # Individual user setup
├── manifests/                         # OpenShift manifests
│   └── vscode-server/                 # VSCode deployment configs
│       ├── namespace.yaml             # VSCode namespace setup
│       ├── deployment-template.yaml   # Per-user VSCode instances
│       ├── configmap.yaml             # VSCode configuration
│       └── serviceaccount.yaml        # RBAC configuration
├── templates/                         # Content templates
│   ├── email/                         # Email templates
│   └── vscode-workspace-content.yaml  # VSCode workspace setup
├── user_environments/                 # Generated user configs
│   ├── .env01, .env02, ...            # Individual user environments
│   ├── users.csv                      # User assignment tracking
│   └── logs/                          # Setup and validation logs
├── workshop_emails/                   # Generated email content
│   ├── DELIVERY_INSTRUCTIONS.md       # Email delivery guide
│   ├── workshop_emails.csv            # Mail merge data
│   ├── html/                          # Individual HTML emails
│   └── outlook/                       # Outlook-compatible format
├── docs/                              # Documentation
│   └── multi-user-setup.md           # Complete setup guide
└── playbooks/                         # Workshop exercises
    ├── exercise1-dynamic-inventory.yml
    ├── exercise2-idempotent-resources.yml
    └── exercise3-advanced-automation.yml
```

## 🛠️ Workshop Environment Details

### Per-User Resources
Each workshop participant receives:
- **VSCode Environment**: Browser-based IDE with pre-configured tools
- **AAP Controller**: Dedicated project with job templates and credentials
- **OpenShift Access**: RBAC-configured access to workshop namespaces
- **Persistent Storage**: 2Gi volume for VSCode workspace
- **Personalized Email**: All access details and quick start guide

### VSCode Environment Features
- **Pre-installed Extensions**: Ansible, OpenShift, Python, YAML support
- **Workshop Content**: All exercises and documentation pre-loaded
- **Terminal Access**: Direct `oc` and `ansible` command line tools
- **Persistent Sessions**: Work survives browser restarts
- **Resource Limits**: 500m CPU, 1Gi RAM per instance

### Email Notification Content
Each participant receives a personalized email with:
- 🖥️ **VSCode URL and password** for immediate access
- 🤖 **AAP Controller credentials** and dashboard link
- ☸️ **OpenShift console access** and API endpoints
- 📚 **Workshop materials** and exercise instructions
- 🚀 **Quick start guide** with test commands
- ❓ **Support contact** information

## 📚 Workshop Delivery Workflow

### Pre-Workshop (Instructor Setup)
```bash
# 1. Parse workshop details
./scripts/parse_workshop_details.sh

# 2. Deploy complete infrastructure
./scripts/setup_multi_user.sh --vscode --generate-emails -p 10

# 3. Validate all environments
./scripts/validate_multi_user.sh --full

# 4. Send participant emails (using preferred method)
# See workshop_emails/DELIVERY_INSTRUCTIONS.md

# 5. Test with sample user environment
# Access user01 VSCode and verify all tools work
```

### During Workshop (Monitoring)
```bash
# Monitor VSCode instances
./scripts/manage_vscode.sh status

# Restart problematic instances
./scripts/manage_vscode.sh restart -u 7

# Quick environment validation
./scripts/validate_multi_user.sh --quick

# Get URLs for participant support
./scripts/manage_vscode.sh url -u 5
```

### Post-Workshop (Cleanup)
```bash
# Remove VSCode instances
./scripts/manage_vscode.sh undeploy

# Clean up user environments (optional)
rm -rf user_environments/

# Archive workshop data
tar -czf workshop-$(date +%Y%m%d).tar.gz workshop_emails/ user_environments/logs/
```

## 🔧 Advanced Configuration

### Custom Workshop Settings
```bash
# Set custom workshop details
export WORKSHOP_NAME="Custom AAP Workshop"
export INSTRUCTOR_EMAIL="instructor@company.com"
export EXERCISES_URL="https://your-materials.com"

# Run setup with custom settings
./scripts/setup_multi_user.sh --vscode --generate-emails
```

### Resource Scaling
```bash
# High-parallel setup for large workshops
./scripts/setup_multi_user.sh -p 20 --vscode

# Process users in batches
./scripts/setup_multi_user.sh -u 1-25 --vscode
./scripts/setup_multi_user.sh -u 26-50 --vscode
```

### Troubleshooting
```bash
# Check individual user logs
cat user_environments/logs/setup_user05.log

# Validate specific user environment
./scripts/validate_multi_user.sh -u 5 --full -v

# Check VSCode deployment status
oc get pods -n workshop-vscode

# Restart failed setups
./scripts/setup_multi_user.sh --resume -v
```

## 📖 Documentation

- **[Multi-User Setup Guide](docs/multi-user-setup.md)**: Complete documentation for workshop setup
- **[VSCode Server Guide](docs/multi-user-setup.md#vscode-server-management)**: VSCode deployment and management
- **[Email System Guide](docs/multi-user-setup.md#workshop-email-notifications)**: Email generation and delivery
- **[Troubleshooting Guide](docs/multi-user-setup.md#troubleshooting)**: Common issues and solutions

## 🎓 Workshop Success Metrics

A successful workshop deployment includes:
- ✅ All user environments validated and accessible
- ✅ VSCode instances running with correct permissions
- ✅ AAP Controller projects and job templates created
- ✅ Email notifications delivered to all participants
- ✅ Workshop materials pre-loaded in VSCode workspaces
- ✅ Instructor monitoring and management tools available

## 🆘 Support and Troubleshooting

### Common Issues
- **Environment parsing failures**: Check RHDP export format
- **VSCode deployment issues**: Verify OpenShift permissions and resources
- **Email generation problems**: Ensure all environments are set up correctly
- **Access credential issues**: Validate AAP Controller and OpenShift connectivity

### Getting Help
1. **Check logs**: Review individual user logs in `user_environments/logs/`
2. **Validate environments**: Run full validation with verbose output
3. **Review documentation**: See `docs/multi-user-setup.md` for detailed guidance
4. **Test with single user**: Use `-u 1` flags to test individual setups

## 🚀 Ready to Run Your Workshop?

1. **Clone the repository**
2. **Add your `workshop_details.txt` file**
3. **Run**: `./scripts/setup_multi_user.sh --vscode --generate-emails`
4. **Send emails to participants**
5. **Start teaching!**

---

*This workshop delivery system streamlines the complex process of setting up enterprise-scale AAP and OpenShift training environments, allowing instructors to focus on teaching rather than infrastructure management.*