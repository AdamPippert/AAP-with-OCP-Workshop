#!/bin/bash

# Workshop Email Generation Script
# Generates email content for various delivery methods without requiring SMTP access

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
USER_ENV_DIR="${REPO_ROOT}/user_environments"
OUTPUT_DIR="${REPO_ROOT}/workshop_emails"
LOG_DIR="${USER_ENV_DIR}/logs"

# Workshop configuration
WORKSHOP_NAME="${WORKSHOP_NAME:-Advanced Ansible Automation Platform Workshop}"
INSTRUCTOR_EMAIL="${INSTRUCTOR_EMAIL:-instructor@redhat.com}"
EXERCISES_URL="${EXERCISES_URL:-https://github.com/your-org/workshop-exercises}"
ORGANIZATION="${ORGANIZATION:-Red Hat}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

usage() {
    cat << EOF
Workshop Email Generation System

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -d, --directory DIR     User environments directory (default: user_environments)
    -o, --output DIR        Output directory for generated emails (default: workshop_emails)
    -u, --users RANGE       User range (e.g., 1-5, 3,7,9, or single number)
    --format FORMAT         Output format: html, csv, json, outlook, gmail (default: all)
    --exercises-url URL     URL to workshop exercises
    --instructor EMAIL      Instructor contact email
    --organization ORG      Organization name
    -v, --verbose           Detailed output
    -h, --help              Show this help

OUTPUT FORMATS:
    html        Individual HTML files for each user
    csv         CSV file for mail merge
    json        JSON file for API integration
    outlook     Outlook-compatible format
    gmail       Gmail-compatible format
    all         Generate all formats (default)

EXAMPLES:
    $0                          # Generate all formats for all users
    $0 -u 1-10 --format csv     # Generate CSV for users 1-10
    $0 --format outlook         # Generate Outlook format only
    $0 --exercises-url https://your-workshop.com

DELIVERY OPTIONS:
    1. CSV Mail Merge: Use the CSV file with Outlook or Gmail mail merge
    2. Individual HTML: Copy/paste individual HTML files into email client
    3. JSON API: Use JSON data with email service APIs
    4. Outlook Import: Import the Outlook-compatible file
    5. Gmail Import: Use the Gmail-compatible format

EOF
}

# Parse user range into array
parse_user_range() {
    local range="$1"
    local users=()
    
    if [[ $range =~ ^[0-9]+$ ]]; then
        # Single user
        users=("$range")
    elif [[ $range =~ ^[0-9]+-[0-9]+$ ]]; then
        # Range: 1-10
        local start=$(echo "$range" | cut -d'-' -f1)
        local end=$(echo "$range" | cut -d'-' -f2)
        for ((i=start; i<=end; i++)); do
            users+=("$i")
        done
    elif [[ $range =~ , ]]; then
        # Comma-separated or complex ranges
        IFS=',' read -ra PARTS <<< "$range"
        for part in "${PARTS[@]}"; do
            if [[ $part =~ ^[0-9]+$ ]]; then
                users+=("$part")
            elif [[ $part =~ ^[0-9]+-[0-9]+$ ]]; then
                local start=$(echo "$part" | cut -d'-' -f1)
                local end=$(echo "$part" | cut -d'-' -f2)
                for ((i=start; i<=end; i++)); do
                    users+=("$i")
                done
            fi
        done
    else
        log_error "Invalid user range format: $range"
        return 1
    fi
    
    # Sort and deduplicate
    printf '%s\n' "${users[@]}" | sort -n | uniq
}

# Discover all user environment files
discover_users() {
    local env_dir="$1"
    local users=()
    
    for env_file in "$env_dir"/.env[0-9][0-9]; do
        if [[ -f "$env_file" ]]; then
            local user_num
            user_num=$(basename "$env_file" | sed 's/\.env0*//')
            users+=("$user_num")
        fi
    done
    
    if [[ ${#users[@]} -eq 0 ]]; then
        log_error "No user environment files found in $env_dir"
        return 1
    fi
    
    printf '%s\n' "${users[@]}" | sort -n
}

# Load user environment variables
load_user_env() {
    local user_num="$1"
    local env_dir="$2"
    local env_file="${env_dir}/.env$(printf "%02d" "$user_num")"
    
    if [[ ! -f "$env_file" ]]; then
        log_error "Environment file not found: $env_file"
        return 1
    fi
    
    # Source the environment file
    set -a  # automatically export all variables
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
    
    # Validate required variables
    local required_vars=("USER_EMAIL" "OCP_CLUSTER_DOMAIN" "AAP_URL" "WORKSHOP_GUID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var not found in $env_file"
            return 1
        fi
    done
}

# Get VSCode URL for user
get_vscode_url() {
    local user_num="$1"
    local user_padded
    user_padded=$(printf "%02d" "$user_num")
    
    # Try to get route from OpenShift
    if command -v oc &> /dev/null && oc whoami &> /dev/null; then
        local route_url
        if route_url=$(oc get route "vscode-user${user_padded}" -n workshop-vscode -o jsonpath='{.spec.host}' 2>/dev/null); then
            echo "https://$route_url"
            return 0
        fi
    fi
    
    # Fallback to constructed URL
    if [[ -n "${OCP_CLUSTER_DOMAIN:-}" ]]; then
        echo "https://vscode-user${user_padded}.${OCP_CLUSTER_DOMAIN}"
    else
        echo "VSCode URL not available"
    fi
}

# Get VSCode password for user
get_vscode_password() {
    local user_num="$1"
    local user_padded
    user_padded=$(printf "%02d" "$user_num")
    
    # Try to get password from OpenShift secret
    if command -v oc &> /dev/null && oc whoami &> /dev/null; then
        local password
        if password=$(oc get secret "vscode-user${user_padded}-env" -n workshop-vscode -o jsonpath='{.data.PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null); then
            echo "$password"
            return 0
        fi
    fi
    
    # Generate a readable password if not available
    echo "workshop-user${user_padded}"
}

# Generate HTML email content for a user
generate_html_email() {
    local user_num="$1"
    local user_padded
    user_padded=$(printf "%02d" "$user_num")
    
    # Load user environment
    if ! load_user_env "$user_num" "$USER_ENV_DIR"; then
        return 1
    fi
    
    # Get VSCode details
    local vscode_url vscode_password
    vscode_url=$(get_vscode_url "$user_num")
    vscode_password=$(get_vscode_password "$user_num")
    
    # Generate HTML email content
    cat << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${WORKSHOP_NAME} - Environment Details</title>
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 20px; }
        .header { background: #ee0000; color: white; padding: 20px; border-radius: 5px; text-align: center; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .access-info { background: #f8f9fa; }
        .credentials { background: #fff3cd; border-color: #ffeaa7; }
        .important { background: #d4edda; border-color: #c3e6cb; }
        .code { background: #f1f1f1; font-family: 'Courier New', monospace; padding: 8px; border-radius: 4px; border: 1px solid #ddd; display: inline-block; }
        .url { color: #0066cc; text-decoration: none; font-weight: bold; }
        .url:hover { text-decoration: underline; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        td { padding: 12px 8px; border-bottom: 1px solid #eee; vertical-align: top; }
        td:first-child { font-weight: bold; width: 200px; color: #666; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 2px solid #ee0000; color: #666; text-align: center; }
        .logo { margin-bottom: 10px; }
        .quick-start { background: #e7f3ff; border-left: 4px solid #0066cc; }
        .step { margin: 10px 0; padding: 10px; background: white; border-radius: 4px; }
        .step-number { background: #ee0000; color: white; border-radius: 50%; width: 25px; height: 25px; display: inline-flex; align-items: center; justify-content: center; margin-right: 10px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo">🎓</div>
        <h1>${WORKSHOP_NAME}</h1>
        <h2>Your Personal Environment Details</h2>
        <p style="margin: 0; opacity: 0.9;">Powered by ${ORGANIZATION}</p>
    </div>

    <div class="section important">
        <h3>👋 Welcome to Your Workshop Environment!</h3>
        <p>Hello <strong>${USER_EMAIL}</strong>,</p>
        <p>Your personalized workshop environment is ready and waiting for you! Everything has been pre-configured so you can focus on learning.</p>
        <table style="background: white; border-radius: 5px;">
            <tr>
                <td>Your User ID:</td>
                <td><span class="code">User ${user_padded}</span></td>
            </tr>
            <tr>
                <td>Workshop GUID:</td>
                <td><span class="code">${WORKSHOP_GUID}</span></td>
            </tr>
            <tr>
                <td>Environment:</td>
                <td><span class="code">${OCP_CLUSTER_DOMAIN}</span></td>
            </tr>
        </table>
    </div>

    <div class="section quick-start">
        <h3>🚀 Quick Start Guide</h3>
        <p><strong>Get started in 3 easy steps:</strong></p>
        
        <div class="step">
            <span class="step-number">1</span>
            <strong>Access Your VSCode Environment</strong><br>
            Click your VSCode URL below and enter your password when prompted.
        </div>
        
        <div class="step">
            <span class="step-number">2</span>
            <strong>Open the Terminal</strong><br>
            In VSCode, go to Terminal → New Terminal (or press Ctrl+`).
        </div>
        
        <div class="step">
            <span class="step-number">3</span>
            <strong>Start the Workshop</strong><br>
            Follow the instructions in the README.md file that opens automatically.
        </div>
    </div>

    <div class="section access-info">
        <h3>💻 VSCode Development Environment</h3>
        <p>Your browser-based development environment with all tools pre-installed:</p>
        <table>
            <tr>
                <td>🌐 VSCode URL:</td>
                <td><a href="${vscode_url}" class="url">${vscode_url}</a></td>
            </tr>
            <tr>
                <td>🔐 Password:</td>
                <td><span class="code">${vscode_password}</span></td>
            </tr>
            <tr>
                <td>📁 Workspace:</td>
                <td>Pre-loaded with all workshop exercises and tools</td>
            </tr>
        </table>
        <p><em>💡 Tip: Bookmark your VSCode URL for easy access!</em></p>
    </div>

    <div class="section access-info">
        <h3>🤖 Ansible Automation Platform</h3>
        <p>Your dedicated AAP Controller for automation workflows:</p>
        <table>
            <tr>
                <td>🌐 Controller URL:</td>
                <td><a href="${AAP_URL}" class="url">${AAP_URL}</a></td>
            </tr>
            <tr>
                <td>👤 Username:</td>
                <td><span class="code">${AAP_USERNAME}</span></td>
            </tr>
            <tr>
                <td>🔐 Password:</td>
                <td><span class="code">${AAP_PASSWORD}</span></td>
            </tr>
        </table>
    </div>

    <div class="section access-info">
        <h3>☸️ OpenShift Container Platform</h3>
        <p>Your OpenShift cluster for container orchestration:</p>
        <table>
            <tr>
                <td>🌐 Web Console:</td>
                <td><a href="${OCP_CONSOLE_URL}" class="url">${OCP_CONSOLE_URL}</a></td>
            </tr>
            <tr>
                <td>🔧 API Server:</td>
                <td><span class="code">${OCP_API_URL}</span></td>
            </tr>
            <tr>
                <td>🏷️ Cluster Domain:</td>
                <td><span class="code">${OCP_CLUSTER_DOMAIN}</span></td>
            </tr>
        </table>
    </div>

    <div class="section important">
        <h3>📚 Workshop Materials</h3>
        <p><strong>Everything you need is already loaded in your VSCode environment!</strong></p>
        <ul>
            <li>📖 <strong>Exercise Instructions:</strong> Available in your VSCode workspace</li>
            <li>🔗 <strong>Online Materials:</strong> <a href="${EXERCISES_URL}" class="url">${EXERCISES_URL}</a></li>
            <li>⚡ <strong>Quick Commands:</strong> Listed in the README.md file</li>
        </ul>
    </div>

    <div class="section credentials">
        <h3>🔧 Advanced Access (Optional)</h3>
        <p>For advanced troubleshooting, SSH access to your environment:</p>
        <table>
            <tr>
                <td>🖥️ SSH Host:</td>
                <td><span class="code">${SSH_HOST}</span></td>
            </tr>
            <tr>
                <td>🚪 SSH Port:</td>
                <td><span class="code">${SSH_PORT}</span></td>
            </tr>
            <tr>
                <td>👤 Username:</td>
                <td><span class="code">${SSH_USER}</span></td>
            </tr>
            <tr>
                <td>🔐 Password:</td>
                <td><span class="code">${SSH_PASSWORD}</span></td>
            </tr>
        </table>
        <p><em>Note: You probably won't need SSH access - everything can be done in VSCode!</em></p>
    </div>

    <div class="section">
        <h3>🧪 Test Your Environment</h3>
        <p>Once you're in VSCode, verify everything works with these commands:</p>
        <div class="code" style="display: block; white-space: pre-line; margin: 10px 0;"># Test OpenShift connection
oc whoami

# Test AAP connection  
curl -k \${AAP_URL}/api/v2/ping/

# Install workshop dependencies
ansible-galaxy collection install -r requirements.yml
pip install -r requirements.txt

# Run your first exercise
ansible-playbook playbooks/exercise1-dynamic-inventory.yml -v</div>
    </div>

    <div class="section">
        <h3>❓ Need Help?</h3>
        <p><strong>We're here to help you succeed!</strong></p>
        <ul>
            <li>🆘 <strong>Technical Issues:</strong> Contact <a href="mailto:${INSTRUCTOR_EMAIL}" class="url">${INSTRUCTOR_EMAIL}</a></li>
            <li>📋 <strong>Exercise Questions:</strong> Check the README.md in your VSCode workspace</li>
            <li>💬 <strong>During the Workshop:</strong> Ask questions in chat or raise your hand</li>
            <li>📞 <strong>Urgent Issues:</strong> Get the instructor's attention immediately</li>
        </ul>
    </div>

    <div class="footer">
        <h4>🎯 Ready to Start?</h4>
        <p><strong>Click your VSCode URL above and let's begin learning!</strong></p>
        <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;">
        <p>Workshop: ${WORKSHOP_NAME}</p>
        <p>Environment: ${WORKSHOP_GUID} | User: ${user_padded} | Generated: $(date)</p>
        <p>Questions? Contact: <a href="mailto:${INSTRUCTOR_EMAIL}" class="url">${INSTRUCTOR_EMAIL}</a></p>
    </div>
</body>
</html>
EOF
}

# Generate CSV format for mail merge
generate_csv_format() {
    local users=("$@")
    local csv_file="${OUTPUT_DIR}/workshop_emails.csv"
    
    # Create CSV header
    cat << EOF > "$csv_file"
UserNumber,Email,VSCodeURL,VSCodePassword,AAPURL,AAPUsername,AAPPassword,OpenShiftConsole,OpenShiftAPI,ClusterDomain,WorkshopGUID,SSHHost,SSHPort,SSHUser,SSHPassword,ExercisesURL,InstructorEmail
EOF
    
    # Process each user
    for user in "${users[@]}"; do
        local user_padded
        user_padded=$(printf "%02d" "$user")
        
        if ! load_user_env "$user" "$USER_ENV_DIR"; then
            log_warn "Skipping user $user_padded due to environment load failure"
            continue
        fi
        
        local vscode_url vscode_password
        vscode_url=$(get_vscode_url "$user")
        vscode_password=$(get_vscode_password "$user")
        
        # Escape commas and quotes in CSV
        local escaped_values=(
            "$user_padded"
            "$USER_EMAIL"
            "$vscode_url"
            "$vscode_password"
            "$AAP_URL"
            "$AAP_USERNAME"
            "$AAP_PASSWORD"
            "$OCP_CONSOLE_URL"
            "$OCP_API_URL"
            "$OCP_CLUSTER_DOMAIN"
            "$WORKSHOP_GUID"
            "$SSH_HOST"
            "$SSH_PORT"
            "$SSH_USER"
            "$SSH_PASSWORD"
            "$EXERCISES_URL"
            "$INSTRUCTOR_EMAIL"
        )
        
        # Write CSV row
        IFS=','
        echo "${escaped_values[*]}" >> "$csv_file"
    done
    
    log_success "CSV file created: $csv_file"
}

# Generate JSON format for API integration
generate_json_format() {
    local users=("$@")
    local json_file="${OUTPUT_DIR}/workshop_emails.json"
    
    echo "{" > "$json_file"
    echo "  \"workshop\": {" >> "$json_file"
    echo "    \"name\": \"$WORKSHOP_NAME\"," >> "$json_file"
    echo "    \"instructor\": \"$INSTRUCTOR_EMAIL\"," >> "$json_file"
    echo "    \"exercises_url\": \"$EXERCISES_URL\"," >> "$json_file"
    echo "    \"generated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" >> "$json_file"
    echo "  }," >> "$json_file"
    echo "  \"users\": [" >> "$json_file"
    
    local first=true
    for user in "${users[@]}"; do
        local user_padded
        user_padded=$(printf "%02d" "$user")
        
        if ! load_user_env "$user" "$USER_ENV_DIR"; then
            log_warn "Skipping user $user_padded due to environment load failure"
            continue
        fi
        
        local vscode_url vscode_password
        vscode_url=$(get_vscode_url "$user")
        vscode_password=$(get_vscode_password "$user")
        
        if [[ "$first" == "false" ]]; then
            echo "    }," >> "$json_file"
        fi
        first=false
        
        cat << EOF >> "$json_file"
    {
      "user_number": "$user_padded",
      "email": "$USER_EMAIL",
      "workshop_guid": "$WORKSHOP_GUID",
      "vscode": {
        "url": "$vscode_url",
        "password": "$vscode_password"
      },
      "aap": {
        "url": "$AAP_URL",
        "username": "$AAP_USERNAME",
        "password": "$AAP_PASSWORD"
      },
      "openshift": {
        "console_url": "$OCP_CONSOLE_URL",
        "api_url": "$OCP_API_URL",
        "cluster_domain": "$OCP_CLUSTER_DOMAIN"
      },
      "ssh": {
        "host": "$SSH_HOST",
        "port": "$SSH_PORT",
        "username": "$SSH_USER",
        "password": "$SSH_PASSWORD"
      }
EOF
    done
    
    if [[ "$first" == "false" ]]; then
        echo "    }" >> "$json_file"
    fi
    
    echo "  ]" >> "$json_file"
    echo "}" >> "$json_file"
    
    log_success "JSON file created: $json_file"
}

# Generate Outlook-compatible format
generate_outlook_format() {
    local users=("$@")
    local outlook_dir="${OUTPUT_DIR}/outlook"
    mkdir -p "$outlook_dir"
    
    # Create a simple text format that's easy to copy/paste
    for user in "${users[@]}"; do
        local user_padded
        user_padded=$(printf "%02d" "$user")
        
        if ! load_user_env "$user" "$USER_ENV_DIR"; then
            log_warn "Skipping user $user_padded due to environment load failure"
            continue
        fi
        
        local vscode_url vscode_password
        vscode_url=$(get_vscode_url "$user")
        vscode_password=$(get_vscode_password "$user")
        
        local outlook_file="${outlook_dir}/user${user_padded}_email.txt"
        cat << EOF > "$outlook_file"
To: ${USER_EMAIL}
Subject: ${WORKSHOP_NAME} - Your Environment Details (User ${user_padded})

Hello ${USER_EMAIL},

Your workshop environment is ready! Here are your access details:

🚀 QUICK START:
1. Click your VSCode URL: ${vscode_url}
2. Password: ${vscode_password}
3. Open Terminal in VSCode and follow the README.md

💻 VSCODE ENVIRONMENT:
URL: ${vscode_url}
Password: ${vscode_password}

🤖 ANSIBLE AUTOMATION PLATFORM:
URL: ${AAP_URL}
Username: ${AAP_USERNAME}
Password: ${AAP_PASSWORD}

☸️ OPENSHIFT CONSOLE:
URL: ${OCP_CONSOLE_URL}
API: ${OCP_API_URL}

📚 WORKSHOP MATERIALS:
${EXERCISES_URL}

❓ NEED HELP?
Contact: ${INSTRUCTOR_EMAIL}

Your Environment: User ${user_padded} | GUID: ${WORKSHOP_GUID}

Ready to start learning? Click your VSCode URL above!

Best regards,
${WORKSHOP_NAME} Team
EOF
    done
    
    log_success "Outlook format created in: $outlook_dir"
}

# Generate Gmail-compatible format
generate_gmail_format() {
    local users=("$@")
    local gmail_file="${OUTPUT_DIR}/gmail_import.txt"
    
    echo "# Gmail Import Format for ${WORKSHOP_NAME}" > "$gmail_file"
    echo "# Copy and paste each section into Gmail compose window" >> "$gmail_file"
    echo "# Generated: $(date)" >> "$gmail_file"
    echo "" >> "$gmail_file"
    
    for user in "${users[@]}"; do
        local user_padded
        user_padded=$(printf "%02d" "$user")
        
        if ! load_user_env "$user" "$USER_ENV_DIR"; then
            log_warn "Skipping user $user_padded due to environment load failure"
            continue
        fi
        
        local vscode_url vscode_password
        vscode_url=$(get_vscode_url "$user")
        vscode_password=$(get_vscode_password "$user")
        
        cat << EOF >> "$gmail_file"
========================================
TO: ${USER_EMAIL}
SUBJECT: ${WORKSHOP_NAME} - Your Environment is Ready! (User ${user_padded})
========================================

Hello!

Your ${WORKSHOP_NAME} environment is ready! 🎉

🚀 QUICK START:
• VSCode URL: ${vscode_url}
• Password: ${vscode_password}
• Click the URL, enter password, open terminal, follow README.md

🔗 YOUR ACCESS DETAILS:

VSCode Environment: ${vscode_url}
Password: ${vscode_password}

AAP Controller: ${AAP_URL}
Username: ${AAP_USERNAME}
Password: ${AAP_PASSWORD}

OpenShift Console: ${OCP_CONSOLE_URL}

Workshop Materials: ${EXERCISES_URL}

Questions? Email: ${INSTRUCTOR_EMAIL}

User: ${user_padded} | GUID: ${WORKSHOP_GUID}

Ready to learn? Click your VSCode URL above and let's get started! 🚀

EOF
    done
    
    log_success "Gmail format created: $gmail_file"
}

# Main generation function
generate_emails() {
    local users=("$@")
    local formats=("$1")
    
    # Remove format from users array
    users=("${users[@]:1}")
    
    mkdir -p "$OUTPUT_DIR"
    
    local total_users=${#users[@]}
    log_info "Generating email content for $total_users users in format(s): $formats"
    
    # Generate individual HTML files
    if [[ "$formats" == "all" || "$formats" == *"html"* ]]; then
        log_info "Generating HTML files..."
        local html_dir="${OUTPUT_DIR}/html"
        mkdir -p "$html_dir"
        
        for user in "${users[@]}"; do
            local user_padded
            user_padded=$(printf "%02d" "$user")
            local html_file="${html_dir}/user${user_padded}_email.html"
            
            if generate_html_email "$user" > "$html_file"; then
                log_info "HTML email created for user $user_padded: $html_file"
            else
                log_warn "Failed to generate HTML for user $user_padded"
            fi
        done
        log_success "HTML files created in: $html_dir"
    fi
    
    # Generate CSV format
    if [[ "$formats" == "all" || "$formats" == *"csv"* ]]; then
        log_info "Generating CSV format..."
        generate_csv_format "${users[@]}"
    fi
    
    # Generate JSON format
    if [[ "$formats" == "all" || "$formats" == *"json"* ]]; then
        log_info "Generating JSON format..."
        generate_json_format "${users[@]}"
    fi
    
    # Generate Outlook format
    if [[ "$formats" == "all" || "$formats" == *"outlook"* ]]; then
        log_info "Generating Outlook format..."
        generate_outlook_format "${users[@]}"
    fi
    
    # Generate Gmail format
    if [[ "$formats" == "all" || "$formats" == *"gmail"* ]]; then
        log_info "Generating Gmail format..."
        generate_gmail_format "${users[@]}"
    fi
    
    # Create delivery instructions
    create_delivery_instructions
    
    log_success "Email generation complete! Check the $OUTPUT_DIR directory."
}

# Create delivery instructions
create_delivery_instructions() {
    local instructions_file="${OUTPUT_DIR}/DELIVERY_INSTRUCTIONS.md"
    
    cat << EOF > "$instructions_file"
# Workshop Email Delivery Instructions

Generated: $(date)
Workshop: ${WORKSHOP_NAME}
Total Users: $(find "${OUTPUT_DIR}" -name "*.html" 2>/dev/null | wc -l)

## Available Formats

### 1. CSV Mail Merge (\`workshop_emails.csv\`)
**Best for: Outlook or Gmail mail merge**
- Import the CSV file into Outlook or Google Sheets
- Create a mail merge template
- Send personalized emails to all users at once

**Outlook Mail Merge Steps:**
1. Open Outlook
2. Go to Mailings → Start Mail Merge → E-mail Messages
3. Select Recipients → Use an Existing List
4. Choose \`workshop_emails.csv\`
5. Write your message using merge fields
6. Complete the merge

### 2. Individual HTML Files (\`html/\` directory)
**Best for: Copy/paste into any email client**
- Each user has a dedicated HTML file
- Copy the HTML content and paste into your email client
- Files are named: \`user01_email.html\`, \`user02_email.html\`, etc.

### 3. JSON Format (\`workshop_emails.json\`)
**Best for: API integration or custom scripts**
- Structured data for programmatic email sending
- Can be used with email service APIs like SendGrid, Mailgun, etc.
- Contains all user data in a structured format

### 4. Outlook Format (\`outlook/\` directory)
**Best for: Copy/paste into Outlook**
- Plain text format optimized for Outlook
- Each file contains the complete email content
- Easy to copy and paste directly

### 5. Gmail Format (\`gmail_import.txt\`)
**Best for: Copy/paste into Gmail**
- Single file with all emails formatted for Gmail
- Each email section is clearly marked
- Optimized for Gmail's compose window

## Recommended Delivery Methods

### Option A: Gmail Mail Merge (Recommended)
1. Install "Mail Merge" add-on in Google Sheets
2. Import \`workshop_emails.csv\` into Google Sheets
3. Use the mail merge add-on to send personalized emails
4. Track delivery and opens

### Option B: Manual Individual Emails
1. Open the \`html/\` directory
2. For each user:
   - Open their HTML file in a browser
   - Copy the rendered content
   - Paste into a new email in your email client
   - Send to the user's email address

### Option C: Outlook Mail Merge
1. Use the CSV file with Outlook's mail merge feature
2. Create a template email with merge fields
3. Send to all users at once

### Option D: Custom Script with JSON
1. Use the JSON file with a custom email sending script
2. Integrate with your preferred email service API
3. Automate the entire process

## Email Content Summary

Each email contains:
- ✅ Personalized greeting with user email
- ✅ VSCode environment URL and password
- ✅ AAP Controller access details
- ✅ OpenShift console access
- ✅ Workshop materials link
- ✅ SSH access for troubleshooting
- ✅ Quick start instructions
- ✅ Contact information for help

## Testing

Before sending to all users:
1. Send a test email to yourself using any format
2. Verify all links work correctly
3. Check that VSCode passwords are correct
4. Confirm formatting looks good in your email client

## Troubleshooting

**Missing VSCode passwords?**
- Run: \`./scripts/manage_vscode.sh status\`
- Ensure VSCode instances are deployed

**Links not working?**  
- Verify OpenShift routes are created
- Check that all services are running

**Email formatting issues?**
- HTML emails work best in modern email clients
- Use plain text versions for older clients

## Questions?

Contact: ${INSTRUCTOR_EMAIL}

Happy workshopping! 🚀
EOF
    
    log_success "Delivery instructions created: $instructions_file"
}

# Main function
main() {
    local env_dir="$USER_ENV_DIR"
    local output_dir="$OUTPUT_DIR"
    local users_range=""
    local format="all"
    local verbose="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--directory)
                env_dir="$2"
                shift 2
                ;;
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -u|--users)
                users_range="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --exercises-url)
                EXERCISES_URL="$2"
                shift 2
                ;;
            --instructor)
                INSTRUCTOR_EMAIL="$2"
                shift 2
                ;;
            --organization)
                ORGANIZATION="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Update global variables
    USER_ENV_DIR="$env_dir"
    OUTPUT_DIR="$output_dir"
    LOG_DIR="${USER_ENV_DIR}/logs"
    
    # Validate environment directory
    if [[ ! -d "$USER_ENV_DIR" ]]; then
        log_error "Environment directory not found: $USER_ENV_DIR"
        exit 1
    fi
    
    # Determine users to process
    local users=()
    if [[ -n "$users_range" ]]; then
        readarray -t users < <(parse_user_range "$users_range")
    else
        readarray -t users < <(discover_users "$USER_ENV_DIR")
    fi
    
    if [[ ${#users[@]} -eq 0 ]]; then
        log_error "No users to process"
        exit 1
    fi
    
    log_info "Processing ${#users[@]} users: ${users[*]}"
    
    # Generate emails
    if generate_emails "$format" "${users[@]}"; then
        echo
        log_success "✅ Email generation complete!"
        log_info "📁 Output directory: $OUTPUT_DIR"
        log_info "📖 See DELIVERY_INSTRUCTIONS.md for next steps"
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"