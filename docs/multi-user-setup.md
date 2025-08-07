# Multi-User Workshop Setup Guide

This guide covers setting up the AAP Workshop for multiple users simultaneously using the bulk workshop details export.

## Overview

The multi-user setup system allows workshop instructors to:
- Parse bulk workshop details from RHDP exports
- Create individual environment configurations for each user
- Run parallel setup processes for all users
- Validate and monitor multiple environments
- Track user assignments and progress

## Quick Start

### 1. Parse Workshop Details

First, ensure you have the `workshop_details.txt` file from RHDP in the repository root, then parse it:

```bash
# Parse the bulk export file
./scripts/parse_workshop_details.sh

# Or with custom options
./scripts/parse_workshop_details.sh -f custom_details.txt -v
```

This creates:
- `user_environments/.env01`, `.env02`, etc. (individual user configs)
- `user_environments/users.csv` (user assignment tracking)
- `user_environments/summary.txt` (parse summary)

### 2. Run Multi-User Setup

```bash
# Setup all users (default: 5 parallel processes)
./scripts/setup_multi_user.sh

# Or with custom options
./scripts/setup_multi_user.sh -p 10 -u 1-20 -v
```

### 3. Validate Environments

```bash
# Quick validation (connectivity only)
./scripts/validate_multi_user.sh

# Full validation (all components)
./scripts/validate_multi_user.sh --full
```

## Detailed Workflow

### Step 1: Workshop Details Format

The system supports multiple workshop details files for large workshops that exceed the user limit per RHDP environment. Files should be named:

- `workshop_details.txt` (primary file)
- `workshop_details2.txt` (additional users)
- `workshop_details3.txt` (more additional users, if needed)
- etc.

Each file should contain bulk export data in this format:

```
Service	Assigned Email	Details
enterprise.aap-product-demos-cnv-aap25.prod-xxxxx

user.email@company.com

Messages

    Your AWS credentials are:
    AWS_ACCESS_KEY_ID: AKIAXXXXXXXX
    AWS_SECRET_ACCESS_KEY: xxxxxxxx
    
    OpenShift Console: https://console-openshift-console.apps.cluster-xxxxx.dynamic.redhatworkshops.io
    OpenShift API: https://api.cluster-xxxxx.dynamic.redhatworkshops.io:6443
    Automation Controller URL: https://aap-aap.apps.cluster-xxxxx.dynamic.redhatworkshops.io
    Automation Controller Admin Login: admin
    Automation Controller Admin Password: xxxxxxxx
    
    [additional details...]

enterprise.aap-product-demos-cnv-aap25.prod-yyyyy

next.user@company.com

[next user details...]
```

### Step 2: Parsing Process

The parser extracts:
- **User Information**: Email addresses and service IDs
- **AWS Credentials**: Access keys and secrets  
- **OpenShift Details**: Console URLs, API endpoints, cluster domains
- **AAP Configuration**: Controller URLs and admin credentials
- **SSH Access**: Bastion host details and credentials

### Step 3: Environment File Structure

Each user gets a `.envXX` file:

```bash
# Workshop Environment Configuration for User 01
# Generated from workshop_details.txt on [date]
# Email: user@company.com
# Service: enterprise.aap-product-demos-cnv-aap25.prod-xxxxx

# User Assignment
USER_NUMBER=01
USER_EMAIL=user@company.com
SERVICE_ID=enterprise.aap-product-demos-cnv-aap25.prod-xxxxx

# AWS Credentials
AWS_ACCESS_KEY_ID=AKIAXXXXXXXX
AWS_SECRET_ACCESS_KEY=xxxxxxxx

# OpenShift Configuration
OCP_CONSOLE_URL=https://console-openshift-console.apps.cluster-xxxxx.dynamic.redhatworkshops.io
OCP_API_URL=https://api.cluster-xxxxx.dynamic.redhatworkshops.io:6443
OCP_CLUSTER_DOMAIN=apps.cluster-xxxxx.dynamic.redhatworkshops.io
WORKSHOP_GUID=xxxxx

# AAP Configuration
AAP_URL=https://aap-aap.apps.cluster-xxxxx.dynamic.redhatworkshops.io
AAP_USERNAME=admin
AAP_PASSWORD=xxxxxxxx

# SSH Access
SSH_HOST=ssh.ocpvXX.rhdp.net
SSH_PORT=XXXXX
SSH_USER=lab-user
SSH_PASSWORD=xxxxxxxx

# Additional Configuration
USE_PUBLISHED_EE=true
SKIP_INTERACTIVE=true
```

### Step 4: Parallel Setup Execution

The multi-user setup script:
1. **Discovers Users**: Finds all `.envXX` files
2. **Creates Temporary Configs**: Converts `.env` back to `details.txt` format for each user
3. **Runs in Parallel**: Executes `setup_workshop.sh` for multiple users simultaneously
4. **Tracks Progress**: Logs individual user progress and status
5. **Provides Monitoring**: Real-time progress updates

### Step 5: Validation and Monitoring

The validation script checks:
- **Environment Files**: Variable completeness and format
- **Connectivity**: AAP Controller, OpenShift API, SSH bastion
- **Authentication**: AAP and OpenShift credentials
- **Resources**: Workshop namespaces, projects, execution environments

## Command Reference

### parse_workshop_details.sh

```bash
# Basic usage (auto-discovers all files)
./scripts/parse_workshop_details.sh

# Options
-f, --file FILE         Single workshop details file 
-o, --output DIR        Output directory (default: user_environments)
--files FILE1,FILE2     Comma-separated list of files to process
--auto-discover         Auto-discover workshop_details*.txt files (default)
--no-auto-discover      Disable auto-discovery
--dry-run               Preview without creating files
-v, --verbose           Detailed output
-h, --help              Show help

# Examples
./scripts/parse_workshop_details.sh                                    # Auto-discover all files
./scripts/parse_workshop_details.sh -f workshop_details.txt           # Single file only
./scripts/parse_workshop_details.sh --files workshop_details.txt,workshop_details2.txt  # Specific files
./scripts/parse_workshop_details.sh --dry-run -v                      # Preview with details
```

### setup_multi_user.sh

```bash
# Basic usage
./scripts/setup_multi_user.sh

# Options
-d, --directory DIR     User environments directory
-p, --parallel NUM      Max parallel setups (default: 5)
-u, --users RANGE       User range (e.g., 1-5, 3,7,9, or single number)
--resume                Resume failed setups only
--force                 Force re-setup even if completed
--dry-run               Preview without executing
-v, --verbose           Detailed output
-h, --help              Show help
```

### validate_multi_user.sh

```bash
# Basic usage
./scripts/validate_multi_user.sh

# Options
-d, --directory DIR     User environments directory
-u, --users RANGE       User range to validate
--quick                 Quick validation (connectivity only)
--full                  Full validation (all components)
--fix                   Attempt to fix common issues
-v, --verbose           Detailed output
-h, --help              Show help
```

## User Range Formats

All scripts support flexible user range specifications:

```bash
# Single user
-u 5

# Range of users
-u 1-10

# Specific users
-u 1,3,5,7,9

# Multiple ranges (setup script only)
-u 1-5,8-12,15
```

## Output Structure

```
user_environments/
├── .env01                          # User 1 environment
├── .env02                          # User 2 environment
├── ...
├── users.csv                       # User assignment tracking
├── summary.txt                     # Parse summary
└── logs/
    ├── setup_user01.log            # Individual setup logs
    ├── setup_user02.log
    ├── validation_user01.log       # Individual validation logs
    ├── validation_user02.log
    ├── multi_setup_progress.log    # Real-time setup progress
    ├── multi_setup_summary.txt     # Setup summary report
    └── validation_summary.txt      # Validation summary report
```

## Monitoring Progress

### Real-time Monitoring

```bash
# Watch setup progress
tail -f user_environments/logs/multi_setup_progress.log

# Watch individual user setup
tail -f user_environments/logs/setup_user05.log

# Monitor all setups at once
tail -f user_environments/logs/setup_user*.log
```

### Status Checking

```bash
# Check overall progress
cat user_environments/logs/multi_setup_summary.txt

# Check individual user status
ls user_environments/logs/*.status

# View failed setups
grep "failed" user_environments/logs/multi_setup_summary.txt
```

## Common Workflows

### Complete Workshop Setup (New)

```bash
# 1. Parse workshop details
./scripts/parse_workshop_details.sh -v

# 2. Review parsed users
cat user_environments/users.csv

# 3. Setup all users with VSCode servers and generate emails
./scripts/setup_multi_user.sh -p 8 -v --vscode --generate-emails

# 4. Validate all environments
./scripts/validate_multi_user.sh --full

# 5. Check results
cat user_environments/logs/validation_summary.txt

# 6. Review generated emails
ls workshop_emails/
cat workshop_emails/DELIVERY_INSTRUCTIONS.md
```

### Resume Failed Setups

```bash
# Check which setups failed
./scripts/setup_multi_user.sh --dry-run --resume

# Resume only failed setups
./scripts/setup_multi_user.sh --resume -v

# Force re-setup specific users
./scripts/setup_multi_user.sh -u 3,7,12 --force
```

### Partial Workshop Setup

```bash
# Setup only specific user range
./scripts/setup_multi_user.sh -u 1-10

# Setup specific problematic users
./scripts/setup_multi_user.sh -u 5,8,15 --force

# High-parallel setup for large workshops
./scripts/setup_multi_user.sh -p 15
```

### Validation and Troubleshooting

```bash
# Quick connectivity check
./scripts/validate_multi_user.sh --quick

# Full validation with details
./scripts/validate_multi_user.sh --full -v

# Validate specific users
./scripts/validate_multi_user.sh -u 1-5 --full

# Attempt automatic fixes
./scripts/validate_multi_user.sh --fix
```

## Performance Considerations

### Parallel Processing

- **Default**: 5 parallel setups (conservative)
- **Recommended**: 8-10 for most systems
- **Maximum**: 15-20 (depends on system resources and network)

### Resource Usage

Each parallel setup process:
- **Memory**: ~100-200MB per process
- **Network**: Moderate (API calls, image pulls)
- **Disk**: ~500MB per user (execution environments)

### Optimization Tips

```bash
# Use published execution environments
export USE_PUBLISHED_EE=true

# Increase parallel processes for powerful systems
./scripts/setup_multi_user.sh -p 12

# Process in batches for large workshops
./scripts/setup_multi_user.sh -u 1-20
./scripts/setup_multi_user.sh -u 21-40
```

## Troubleshooting

### Common Issues

**Parse Failures:**
```bash
# Check file format
head -20 workshop_details.txt

# Try verbose parsing
./scripts/parse_workshop_details.sh -v --dry-run
```

**Setup Failures:**
```bash
# Check individual logs
cat user_environments/logs/setup_user05.log

# Resume with verbose output
./scripts/setup_multi_user.sh --resume -v

# Try published EE if build fails
export USE_PUBLISHED_EE=true
```

**Validation Failures:**
```bash
# Full validation with details
./scripts/validate_multi_user.sh --full -v -u 5

# Check network connectivity
curl -k https://aap-aap.apps.cluster-xxxxx.dynamic.redhatworkshops.io/api/v2/ping/
```

### Log Analysis

```bash
# Find all failed setups
grep -l "ERROR.*failed" user_environments/logs/setup_user*.log

# Check for common error patterns
grep "TypeError\|ConnectionError\|Authentication" user_environments/logs/setup_user*.log

# Analyze validation results
grep "OVERALL:" user_environments/logs/validation_user*.log
```

### Recovery Procedures

```bash
# Clean up failed user environment
rm user_environments/.env05
rm user_environments/logs/*user05*

# Re-parse single user (manual process)
# Extract user details and recreate .env05

# Re-setup single user
./scripts/setup_multi_user.sh -u 5 --force
```

## VSCode Server Management

The workshop now supports browser-based VSCode development environments for each user, deployed as containers on the OpenShift cluster.

### VSCode Features

- **Browser-based IDE**: Full VSCode experience in the browser
- **Pre-configured Environment**: Ansible extensions and workspace ready
- **Persistent Storage**: User files persist between sessions
- **Individual Instances**: Each user gets their own VSCode server
- **Workshop Integration**: Direct access to OpenShift and AAP resources

### VSCode Deployment

#### Deploy VSCode for All Users

```bash
# During initial setup (recommended)
./scripts/setup_multi_user.sh --vscode

# Or deploy VSCode separately
./scripts/deploy_vscode.sh

# Deploy for specific user range
./scripts/deploy_vscode.sh -u 1-10
```

#### VSCode-Only Setup

```bash
# Skip AAP setup, deploy only VSCode
./scripts/setup_multi_user.sh --vscode-only

# Useful for pre-workshop testing
./scripts/deploy_vscode.sh -u 1-3 --dry-run
```

### VSCode Management Commands

```bash
# Check deployment status
./scripts/manage_vscode.sh status

# Get user access URLs
./scripts/manage_vscode.sh url
./scripts/manage_vscode.sh url -u 1-5      # Specific users

# Restart VSCode instances
./scripts/manage_vscode.sh restart
./scripts/manage_vscode.sh restart -u 3    # Single user

# View logs for troubleshooting
./scripts/manage_vscode.sh logs -u 5

# Remove VSCode instances
./scripts/manage_vscode.sh undeploy
./scripts/manage_vscode.sh undeploy -u 1-5
```

### User Access

Each user accesses their VSCode instance via:
- **URL**: `https://vscode-user##.apps.cluster-xxxxx.dynamic.redhatworkshops.io`
- **Password**: Auto-generated, available in deployment logs
- **Workspace**: Pre-configured with workshop content and tools

### VSCode Workspace Structure

```
/workspace/                    # VSCode workspace root
├── README.md                  # User-specific instructions
├── ansible.cfg               # Ansible configuration
├── requirements.yml           # Collection requirements
├── requirements.txt           # Python requirements
├── playbooks/                 # Workshop playbooks
├── roles/                     # Ansible roles
├── inventory/                 # Dynamic inventory configurations
├── docs/                      # Workshop documentation
└── .vscode/                   # VSCode settings and extensions
    ├── settings.json          # Editor preferences
    ├── extensions.json        # Recommended extensions
    └── workspace.code-workspace # Multi-folder workspace
```

### Pre-installed Tools and Extensions

**Ansible Extensions:**
- `redhat.ansible` - Ansible language support
- `redhat.vscode-yaml` - YAML editing
- `ms-kubernetes-tools.vscode-kubernetes-tools` - Kubernetes integration
- `redhat.vscode-openshift-connector` - OpenShift tools

**Development Tools:**
- `ms-python.python` - Python support
- `ms-python.pylint` - Python linting
- `github.copilot` - AI assistance (if available)

**Pre-configured Commands:**
```bash
# Test connections
oc whoami
curl -k $AAP_URL/api/v2/ping/

# Install dependencies
ansible-galaxy collection install -r requirements.yml
pip install -r requirements.txt

# Run playbooks
ansible-playbook playbooks/exercise1.yml -v
```

### VSCode Resource Configuration

**Per-User Resources:**
- **CPU Request**: 500m (0.5 CPU cores)
- **CPU Limit**: 1000m (1 CPU core)  
- **Memory Request**: 1Gi
- **Memory Limit**: 2Gi
- **Storage**: 2Gi persistent volume

**Namespace Quotas** (example for large workshop):
- **Total CPU Request**: Scales with user count
- **Total CPU Limit**: Scales with user count
- **Total Memory Request**: Scales with user count
- **Total Memory Limit**: Scales with user count
- **Total Storage**: Scales with user count

### Troubleshooting VSCode

#### Common Issues

**VSCode Won't Start:**
```bash
# Check pod status
./scripts/manage_vscode.sh status -u 5

# Check pod logs
./scripts/manage_vscode.sh logs -u 5

# Restart instance
./scripts/manage_vscode.sh restart -u 5
```

**Access Issues:**
```bash
# Verify route exists
oc get routes -n workshop-vscode | grep user05

# Check service connectivity
oc get svc -n workshop-vscode | grep user05

# Test from inside cluster
oc exec -n workshop-vscode deployment/vscode-user05 -- curl localhost:8080/healthz
```

**Storage Issues:**
```bash
# Check PVC status
oc get pvc -n workshop-vscode | grep user05

# Check storage class
oc get storageclass

# Recreate with different storage class (if needed)
./scripts/manage_vscode.sh undeploy -u 5
# Edit manifests/vscode-server/deployment-template.yaml
./scripts/deploy_vscode.sh -u 5
```

### Workshop Integration Workflow

#### Pre-Workshop (Instructor)

```bash
# 1. Complete multi-user setup with VSCode
./scripts/parse_workshop_details.sh
./scripts/setup_multi_user.sh --vscode -p 10

# 2. Validate all environments
./scripts/validate_multi_user.sh --full

# 3. Generate user access information
./scripts/manage_vscode.sh url > user_vscode_urls.txt

# 4. Test sample user environment
# Access user01 VSCode and verify all tools work
```

#### During Workshop (Instructor)

```bash
# Monitor VSCode instances
./scripts/manage_vscode.sh status

# Restart problematic instances
./scripts/manage_vscode.sh restart -u 7

# Help users with access issues
./scripts/manage_vscode.sh url -u 7
```

#### Workshop Delivery (Users)

**User Instructions:**
1. **Access VSCode**: Navigate to provided URL
2. **Login**: Use provided password
3. **Open Terminal**: Terminal → New Terminal
4. **Install Requirements**:
   ```bash
   ansible-galaxy collection install -r requirements.yml
   pip install -r requirements.txt
   ```
5. **Test Connections**:
   ```bash
   oc whoami
   curl -k $AAP_URL/api/v2/ping/
   ```
6. **Start Workshop**: Open `playbooks/` folder and begin exercises

### VSCode Advantages for Workshop Delivery

**For Instructors:**
- **Consistent Environment**: All users have identical setup
- **Easy Troubleshooting**: Direct access to user environments
- **Remote Support**: Can assist users directly in their VSCode
- **Resource Management**: Centralized deployment and monitoring

**For Users:**
- **No Local Setup**: Everything runs in browser
- **Pre-configured Tools**: All required extensions and settings
- **Persistent Sessions**: Work survives browser restarts
- **Integrated Terminal**: Direct access to OpenShift and AAP
- **Modern IDE**: Full VSCode feature set available

## Workshop Email Notifications

The workshop setup can automatically generate personalized email notifications for all participants with their environment details.

### Email Generation

#### Automatic Generation During Setup

```bash
# Generate emails as part of the complete setup
./scripts/setup_multi_user.sh --vscode --generate-emails

# Or generate emails separately after setup
./scripts/generate_workshop_emails.sh
```

#### Manual Email Generation

```bash
# Generate all formats for all users
./scripts/generate_workshop_emails.sh

# Generate specific format for user range
./scripts/generate_workshop_emails.sh -u 1-10 --format csv

# Generate for testing
./scripts/generate_workshop_emails.sh -u 1 --format html -v
```

### Email Delivery Options

The system generates multiple formats to work with different email systems:

#### 1. Gmail Mail Merge (Recommended)
```bash
# Generate CSV format
./scripts/generate_workshop_emails.sh --format csv

# Use Google Sheets mail merge add-on:
# 1. Import workshop_emails/workshop_emails.csv into Google Sheets
# 2. Install "Mail Merge" add-on
# 3. Create email template with merge fields
# 4. Send personalized emails to all users
```

#### 2. Individual HTML Files
```bash
# Generate HTML files
./scripts/generate_workshop_emails.sh --format html

# For each user:
# 1. Open workshop_emails/html/user##_email.html in browser
# 2. Copy the content (Ctrl+A, Ctrl+C)
# 3. Paste into email client and send
```

#### 3. Outlook Mail Merge
```bash
# Generate CSV format
./scripts/generate_workshop_emails.sh --format csv

# Use Outlook mail merge:
# 1. Mailings → Start Mail Merge → E-mail Messages
# 2. Select Recipients → Use Existing List
# 3. Choose workshop_emails.csv
# 4. Create template with merge fields
# 5. Complete merge
```

#### 4. Copy/Paste Format
```bash
# Generate plain text format
./scripts/generate_workshop_emails.sh --format outlook

# Copy content from workshop_emails/outlook/user##_email.txt
# Paste directly into email client
```

### Email Content

Each generated email includes:

**Personalized Information:**
- User's email address and user number
- Workshop GUID and environment details

**Access Credentials:**
- 🖥️ **VSCode Environment**: Direct URL and password
- 🤖 **AAP Controller**: URL, username, and password  
- ☸️ **OpenShift Console**: Web console and API URLs
- 🔧 **SSH Access**: Host, port, and credentials (for troubleshooting)

**Getting Started Guide:**
- Step-by-step quick start instructions
- Links to workshop materials
- Test commands to verify environment
- Instructor contact information

**Visual Design:**
- Professional HTML styling with Red Hat branding
- Mobile-responsive design
- Clear sections and visual hierarchy
- Easy-to-copy credentials in code blocks

### Email Customization

```bash
# Customize email content
./scripts/generate_workshop_emails.sh \
  --exercises-url "https://your-workshop-site.com" \
  --instructor "your-email@redhat.com" \
  --organization "Your Organization"

# Custom subject and content
export WORKSHOP_NAME="Your Custom Workshop Name"
export INSTRUCTOR_EMAIL="instructor@company.com"
./scripts/generate_workshop_emails.sh
```

### Delivery Workflow

#### Pre-Workshop Email Delivery

```bash
# 1. Complete environment setup
./scripts/parse_workshop_details.sh
./scripts/setup_multi_user.sh --vscode --generate-emails

# 2. Review generated emails
ls workshop_emails/
cat workshop_emails/DELIVERY_INSTRUCTIONS.md

# 3. Choose delivery method based on your email system
# - Gmail: Use CSV with mail merge add-on
# - Outlook: Use CSV with built-in mail merge
# - Manual: Use individual HTML files

# 4. Test with one user first
# Open workshop_emails/html/user01_email.html
# Copy content and send test email to yourself

# 5. Send to all users using chosen method
```

#### Email Delivery Best Practices

**Testing:**
1. **Test First**: Send to yourself using user01 data
2. **Verify Links**: Ensure all URLs work correctly
3. **Check Passwords**: Confirm VSCode passwords are valid
4. **Format Check**: Verify email displays correctly

**Timing:**
- **Send 24-48 hours before workshop**: Gives users time to review
- **Include in calendar invite**: Reference the email in workshop calendar
- **Send reminder**: Day before workshop with key details

**Content Tips:**
- **Clear Subject**: "Workshop Environment Ready - Action Required"
- **Highlight VSCode URL**: Make it prominent and clickable
- **Include Timing**: When workshop starts and time zone
- **Support Contact**: Clear instructor contact information

### Email Templates

The system generates several email formats:

**HTML Email (Recommended):**
- Professional design with branding
- Interactive elements and links
- Mobile-responsive layout
- Copy-paste ready for most email clients

**Plain Text Email:**
- Universal compatibility
- Good for older email systems
- Easy to customize and edit
- Perfect for Outlook automation

**CSV Data:**
- Mail merge compatible
- Structured data format
- Works with Google Sheets, Outlook, etc.
- Enables bulk personalized sending

### Troubleshooting Email Issues

**Missing VSCode Passwords:**
```bash
# Check VSCode deployment status
./scripts/manage_vscode.sh status

# Regenerate emails after VSCode deployment
./scripts/generate_workshop_emails.sh --format html
```

**Broken Links:**
```bash
# Verify OpenShift routes
oc get routes -n workshop-vscode
oc get routes -n workshop-aap

# Check service status
./scripts/validate_multi_user.sh --quick
```

**Email Formatting Issues:**
```bash
# Generate plain text version
./scripts/generate_workshop_emails.sh --format outlook

# Use individual files for problem users
ls workshop_emails/html/user*.html
```

### Email Delivery Integration

**Integration with Calendar Invites:**
```
Subject: AAP Workshop - Environment Ready!

Your workshop environment is prepared and ready to go!

🎯 Quick Access: [Your VSCode URL]
📧 Details: Check the email we sent with all your credentials
📅 Workshop Time: [Date/Time] 
📍 Location: [Virtual Meeting Link]

See you there!
```

**Follow-up Email Templates:**
- **Day Before**: Reminder with key links
- **Day Of**: Last-minute access instructions  
- **Post-Workshop**: Thank you and next steps

### Advanced Email Features

**Dynamic Content:**
- Personalized workshop materials based on user role
- Environment-specific troubleshooting links
- Customized exercise recommendations

**Analytics and Tracking:**
- Link click tracking (if using email service)
- Delivery confirmation
- User engagement metrics

**Automated Follow-up:**
- Scheduled reminder emails
- Post-workshop survey distribution
- Certificate delivery automation

## Best Practices

### Pre-Setup

1. **Verify File Format**: Use `--dry-run` to preview parsing
2. **Check Disk Space**: Ensure adequate space for all users
3. **Test Network**: Verify connectivity to RHDP environments
4. **Set Parallel Limit**: Start conservative, increase as needed

### During Setup

1. **Monitor Progress**: Use `tail -f` on progress logs
2. **Check Resource Usage**: Monitor system load and memory
3. **Early Validation**: Validate a few users before processing all
4. **Staged Approach**: Process in batches for large workshops

### Post-Setup

1. **Full Validation**: Run comprehensive validation on all users
2. **Document Issues**: Note any problematic environments
3. **User Communication**: Provide users with their environment details
4. **Backup Configs**: Save successful configurations for future reference

## Integration with Workshop Delivery

### Pre-Workshop

```bash
# 1. Parse and setup all environments
./scripts/parse_workshop_details.sh
./scripts/setup_multi_user.sh

# 2. Validate everything is working
./scripts/validate_multi_user.sh --full

# 3. Generate user assignments
cat user_environments/users.csv
```

### During Workshop

```bash
# Monitor user environments
tail -f user_environments/logs/validation_*.log

# Quick health check
./scripts/validate_multi_user.sh --quick

# Fix specific user issues
./scripts/setup_multi_user.sh -u 7 --force
```

### Post-Workshop

```bash
# Cleanup (if needed)
rm -rf user_environments/
rm workshop_details.txt
```

This multi-user setup system significantly reduces the workshop preparation time and provides comprehensive monitoring and validation capabilities for managing multiple user environments simultaneously.