#!/bin/bash

# Workshop Email Notification Script
# Sends environment details to workshop participants

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
USER_ENV_DIR="${REPO_ROOT}/user_environments"
EMAIL_TEMPLATES_DIR="${REPO_ROOT}/templates/email"
LOG_DIR="${USER_ENV_DIR}/logs"

# Email configuration - can be overridden by environment variables
SMTP_SERVER="${SMTP_SERVER:-smtp.gmail.com}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USERNAME="${SMTP_USERNAME:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
FROM_EMAIL="${FROM_EMAIL:-workshop@company.com}"
FROM_NAME="${FROM_NAME:-AAP Workshop Team}"
WORKSHOP_NAME="${WORKSHOP_NAME:-Advanced Ansible Automation Platform Workshop}"
INSTRUCTOR_EMAIL="${INSTRUCTOR_EMAIL:-instructor@company.com}"
EXERCISES_URL="${EXERCISES_URL:-https://github.com/your-org/workshop-exercises}"

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
Workshop Email Notification System

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -d, --directory DIR     User environments directory (default: user_environments)
    -u, --users RANGE       User range (e.g., 1-5, 3,7,9, or single number)
    -t, --template FILE     Email template file (default: auto-generated)
    --smtp-server HOST      SMTP server hostname
    --smtp-port PORT        SMTP server port (default: 587)
    --smtp-user USER        SMTP username
    --smtp-pass PASS        SMTP password
    --from-email EMAIL      From email address
    --from-name NAME        From display name
    --subject SUBJECT       Email subject line
    --test-email EMAIL      Send test email to specified address
    --dry-run               Generate emails without sending
    -v, --verbose           Detailed output
    -h, --help              Show this help

ENVIRONMENT VARIABLES:
    SMTP_SERVER             SMTP server hostname
    SMTP_PORT               SMTP server port
    SMTP_USERNAME           SMTP authentication username
    SMTP_PASSWORD           SMTP authentication password
    FROM_EMAIL              From email address
    FROM_NAME               From display name
    WORKSHOP_NAME           Workshop title
    INSTRUCTOR_EMAIL        Instructor contact email
    EXERCISES_URL           URL to workshop exercises

EXAMPLES:
    $0                          # Send emails to all users
    $0 -u 1-10                  # Send to users 1-10
    $0 --test-email me@test.com # Send test email
    $0 --dry-run -v             # Preview emails

PREREQUISITES:
    - Python 3 with smtplib (usually included)
    - Valid SMTP credentials configured
    - User environment files (.envXX) must exist
    - VSCode deployments should be completed

EOF
}

# Check if Python is available for email sending
check_python() {
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required for sending emails"
        return 1
    fi
    
    # Test if required modules are available
    if ! python3 -c "import smtplib, email.mime.text, email.mime.multipart" 2>/dev/null; then
        log_error "Required Python email modules not available"
        return 1
    fi
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
        if password=$(oc get secret "vscode-user${user_padded}-env" -n workshop-vscode -o jsonpath='{.data.PASSWORD}' 2>/dev/null | base64 -d); then
            echo "$password"
            return 0
        fi
    fi
    
    # Fallback message
    echo "Please contact instructor for VSCode password"
}

# Generate email content for a user
generate_email_content() {
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
        .header { background: #0066cc; color: white; padding: 20px; border-radius: 5px; text-align: center; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .access-info { background: #f8f9fa; }
        .credentials { background: #fff3cd; border-color: #ffeaa7; }
        .important { background: #d4edda; border-color: #c3e6cb; }
        .code { background: #f8f9fa; font-family: monospace; padding: 5px; border-radius: 3px; }
        .url { color: #0066cc; text-decoration: none; font-weight: bold; }
        .url:hover { text-decoration: underline; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        td { padding: 8px; border-bottom: 1px solid #eee; }
        td:first-child { font-weight: bold; width: 200px; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <h1>${WORKSHOP_NAME}</h1>
        <h2>Your Environment Details</h2>
    </div>

    <div class="section important">
        <h3>👋 Welcome!</h3>
        <p>Hello <strong>${USER_EMAIL}</strong>,</p>
        <p>Your workshop environment is ready! Below you'll find all the information needed to access your personalized development environment.</p>
        <p><strong>User ID:</strong> ${user_padded} | <strong>Workshop GUID:</strong> ${WORKSHOP_GUID}</p>
    </div>

    <div class="section access-info">
        <h3>🖥️ VSCode Development Environment</h3>
        <p>Your browser-based VSCode environment is pre-configured with all workshop tools and exercises.</p>
        <table>
            <tr>
                <td>VSCode URL:</td>
                <td><a href="${vscode_url}" class="url">${vscode_url}</a></td>
            </tr>
            <tr>
                <td>Password:</td>
                <td><span class="code">${vscode_password}</span></td>
            </tr>
        </table>
        <p><strong>Getting Started:</strong></p>
        <ol>
            <li>Click the VSCode URL above</li>
            <li>Enter the password when prompted</li>
            <li>Open a terminal (Terminal → New Terminal)</li>
            <li>Follow the instructions in the README.md file</li>
        </ol>
    </div>

    <div class="section access-info">
        <h3>🤖 Ansible Automation Platform</h3>
        <p>Your dedicated AAP Controller instance for automation workflows.</p>
        <table>
            <tr>
                <td>Controller URL:</td>
                <td><a href="${AAP_URL}" class="url">${AAP_URL}</a></td>
            </tr>
            <tr>
                <td>Username:</td>
                <td><span class="code">${AAP_USERNAME}</span></td>
            </tr>
            <tr>
                <td>Password:</td>
                <td><span class="code">${AAP_PASSWORD}</span></td>
            </tr>
        </table>
    </div>

    <div class="section access-info">
        <h3>☸️ OpenShift Container Platform</h3>
        <p>Your OpenShift cluster for container orchestration and application deployment.</p>
        <table>
            <tr>
                <td>Web Console:</td>
                <td><a href="${OCP_CONSOLE_URL}" class="url">${OCP_CONSOLE_URL}</a></td>
            </tr>
            <tr>
                <td>API Server:</td>
                <td><span class="code">${OCP_API_URL}</span></td>
            </tr>
            <tr>
                <td>Cluster Domain:</td>
                <td><span class="code">${OCP_CLUSTER_DOMAIN}</span></td>
            </tr>
        </table>
        <p><strong>CLI Access:</strong> Use the terminal in VSCode or download the <code>oc</code> client.</p>
    </div>

    <div class="section important">
        <h3>📚 Workshop Exercises</h3>
        <p>Complete workshop instructions and exercises are available at:</p>
        <p><a href="${EXERCISES_URL}" class="url">${EXERCISES_URL}</a></p>
        <p>All exercises are also pre-loaded in your VSCode workspace in the <code>playbooks/</code> directory.</p>
    </div>

    <div class="section credentials">
        <h3>🔐 SSH Access (Advanced)</h3>
        <p>For advanced troubleshooting, you can access your environment via SSH:</p>
        <table>
            <tr>
                <td>SSH Host:</td>
                <td><span class="code">${SSH_HOST}</span></td>
            </tr>
            <tr>
                <td>SSH Port:</td>
                <td><span class="code">${SSH_PORT}</span></td>
            </tr>
            <tr>
                <td>Username:</td>
                <td><span class="code">${SSH_USER}</span></td>
            </tr>
            <tr>
                <td>Password:</td>
                <td><span class="code">${SSH_PASSWORD}</span></td>
            </tr>
        </table>
    </div>

    <div class="section">
        <h3>🚀 Quick Start Commands</h3>
        <p>Once you're in your VSCode environment, try these commands:</p>
        <div class="code">
# Test your connections<br>
oc whoami<br>
curl -k \${AAP_URL}/api/v2/ping/<br>
<br>
# Install dependencies<br>
ansible-galaxy collection install -r requirements.yml<br>
pip install -r requirements.txt<br>
<br>
# Start with Exercise 1<br>
ansible-playbook playbooks/exercise1-dynamic-inventory.yml -v
        </div>
    </div>

    <div class="section">
        <h3>❓ Need Help?</h3>
        <ul>
            <li><strong>Technical Issues:</strong> Contact <a href="mailto:${INSTRUCTOR_EMAIL}">${INSTRUCTOR_EMAIL}</a></li>
            <li><strong>Exercises:</strong> Check the README.md in your VSCode workspace</li>
            <li><strong>During Workshop:</strong> Ask questions in the chat or raise your hand</li>
        </ul>
    </div>

    <div class="footer">
        <p>This email was generated automatically for the ${WORKSHOP_NAME}.</p>
        <p>Workshop Environment ID: ${WORKSHOP_GUID} | User: ${user_padded}</p>
        <p>If you have any issues accessing your environment, please contact the workshop instructor.</p>
    </div>
</body>
</html>
EOF
}

# Send email using Python SMTP
send_email() {
    local to_email="$1"
    local subject="$2"
    local html_content="$3"
    local verbose="$4"
    
    # Create temporary Python script for sending email
    local python_script
    python_script=$(mktemp)
    
    cat << 'EOF' > "$python_script"
#!/usr/bin/env python3
import smtplib
import sys
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import os

def send_email():
    # Get configuration from environment
    smtp_server = os.environ.get('SMTP_SERVER', 'smtp.gmail.com')
    smtp_port = int(os.environ.get('SMTP_PORT', '587'))
    smtp_username = os.environ.get('SMTP_USERNAME', '')
    smtp_password = os.environ.get('SMTP_PASSWORD', '')
    from_email = os.environ.get('FROM_EMAIL', 'workshop@company.com')
    from_name = os.environ.get('FROM_NAME', 'AAP Workshop Team')
    
    # Get email details from command line
    to_email = sys.argv[1]
    subject = sys.argv[2]
    html_content = sys.argv[3]
    verbose = len(sys.argv) > 4 and sys.argv[4] == 'true'
    
    # Validate required settings
    if not smtp_username or not smtp_password:
        print("ERROR: SMTP credentials not configured", file=sys.stderr)
        return False
    
    try:
        # Create message
        msg = MIMEMultipart('alternative')
        msg['Subject'] = subject
        msg['From'] = f"{from_name} <{from_email}>"
        msg['To'] = to_email
        
        # Attach HTML content
        html_part = MIMEText(html_content, 'html')
        msg.attach(html_part)
        
        # Connect to server and send email
        if verbose:
            print(f"Connecting to {smtp_server}:{smtp_port}", file=sys.stderr)
        
        server = smtplib.SMTP(smtp_server, smtp_port)
        server.starttls()
        server.login(smtp_username, smtp_password)
        
        if verbose:
            print(f"Sending email to {to_email}", file=sys.stderr)
        
        server.send_message(msg)
        server.quit()
        
        print(f"Email sent successfully to {to_email}")
        return True
        
    except Exception as e:
        print(f"ERROR: Failed to send email to {to_email}: {e}", file=sys.stderr)
        return False

if __name__ == "__main__":
    success = send_email()
    sys.exit(0 if success else 1)
EOF
    
    # Set environment variables for Python script
    export SMTP_SERVER SMTP_PORT SMTP_USERNAME SMTP_PASSWORD FROM_EMAIL FROM_NAME
    
    # Send the email
    local result
    if python3 "$python_script" "$to_email" "$subject" "$html_content" "$verbose"; then
        result=0
    else
        result=1
    fi
    
    # Cleanup
    rm -f "$python_script"
    return $result
}

# Send emails to users
send_user_emails() {
    local users=("$@")
    local verbose="$1"
    local dry_run="$2"
    local test_email="$3"
    local custom_subject="$4"
    
    # Remove function parameters from users array
    users=("${users[@]:4}")
    
    local subject="${custom_subject:-${WORKSHOP_NAME} - Your Environment Details}"
    local sent=0
    local failed=0
    
    # Validate SMTP configuration
    if [[ "$dry_run" == "false" && "$test_email" == "" ]]; then
        if [[ -z "$SMTP_USERNAME" || -z "$SMTP_PASSWORD" ]]; then
            log_error "SMTP credentials not configured. Set SMTP_USERNAME and SMTP_PASSWORD environment variables."
            return 1
        fi
    fi
    
    # Send to test email if specified
    if [[ -n "$test_email" ]]; then
        log_info "Sending test email to $test_email using user 1 data..."
        
        local html_content
        if html_content=$(generate_email_content 1); then
            if [[ "$dry_run" == "true" ]]; then
                log_info "DRY RUN: Would send test email to $test_email"
                if [[ "$verbose" == "true" ]]; then
                    echo "Subject: $subject"
                    echo "To: $test_email"
                    echo "Content preview: $(echo "$html_content" | head -5)"
                fi
            else
                if send_email "$test_email" "$subject" "$html_content" "$verbose"; then
                    log_success "Test email sent to $test_email"
                else
                    log_error "Failed to send test email to $test_email"
                    return 1
                fi
            fi
        else
            log_error "Failed to generate test email content"
            return 1
        fi
        return 0
    fi
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    local email_log="${LOG_DIR}/email_notifications.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Starting email notifications for ${#users[@]} users" > "$email_log"
    
    # Process each user
    for user in "${users[@]}"; do
        local user_padded
        user_padded=$(printf "%02d" "$user")
        
        log_info "Processing email for user $user_padded..."
        
        # Load user environment
        if ! load_user_env "$user" "$USER_ENV_DIR"; then
            log_error "Failed to load environment for user $user_padded"
            ((failed++))
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] User $user_padded: Failed to load environment" >> "$email_log"
            continue
        fi
        
        # Generate email content
        local html_content
        if ! html_content=$(generate_email_content "$user"); then
            log_error "Failed to generate email content for user $user_padded"
            ((failed++))
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] User $user_padded: Failed to generate email content" >> "$email_log"
            continue
        fi
        
        # Save email content if dry run or verbose
        if [[ "$dry_run" == "true" || "$verbose" == "true" ]]; then
            local email_file="${LOG_DIR}/email_user${user_padded}.html"
            echo "$html_content" > "$email_file"
            log_info "Email content saved to: $email_file"
        fi
        
        if [[ "$dry_run" == "true" ]]; then
            log_info "DRY RUN: Would send email to $USER_EMAIL"
            ((sent++))
        else
            # Send the email
            if send_email "$USER_EMAIL" "$subject" "$html_content" "$verbose"; then
                log_success "Email sent to $USER_EMAIL (user $user_padded)"
                ((sent++))
                echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] User $user_padded: Email sent to $USER_EMAIL" >> "$email_log"
            else
                log_error "Failed to send email to $USER_EMAIL (user $user_padded)"
                ((failed++))
                echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] User $user_padded: Failed to send email to $USER_EMAIL" >> "$email_log"
            fi
        fi
    done
    
    # Summary
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Email notifications complete: $sent sent, $failed failed" >> "$email_log"
    
    log_info "Email notifications complete:"
    log_info "  Sent: $sent"
    log_info "  Failed: $failed"
    
    if [[ $failed -eq 0 ]]; then
        log_success "All emails sent successfully!"
        return 0
    else
        log_error "Some emails failed to send. Check $email_log for details."
        return 1
    fi
}

# Main function
main() {
    local env_dir="$USER_ENV_DIR"
    local users_range=""
    local template_file=""
    local custom_subject=""
    local test_email=""
    local dry_run="false"
    local verbose="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--directory)
                env_dir="$2"
                shift 2
                ;;
            -u|--users)
                users_range="$2"
                shift 2
                ;;
            -t|--template)
                template_file="$2"
                shift 2
                ;;
            --smtp-server)
                SMTP_SERVER="$2"
                shift 2
                ;;
            --smtp-port)
                SMTP_PORT="$2"
                shift 2
                ;;
            --smtp-user)
                SMTP_USERNAME="$2"
                shift 2
                ;;
            --smtp-pass)
                SMTP_PASSWORD="$2"
                shift 2
                ;;
            --from-email)
                FROM_EMAIL="$2"
                shift 2
                ;;
            --from-name)
                FROM_NAME="$2"
                shift 2
                ;;
            --subject)
                custom_subject="$2"
                shift 2
                ;;
            --test-email)
                test_email="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
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
    LOG_DIR="${USER_ENV_DIR}/logs"
    
    # Validate environment directory
    if [[ ! -d "$USER_ENV_DIR" ]]; then
        log_error "Environment directory not found: $USER_ENV_DIR"
        exit 1
    fi
    
    # Check prerequisites
    if ! check_python; then
        exit 1
    fi
    
    # Determine users to process
    local users=()
    if [[ -n "$users_range" ]]; then
        local user_list
        user_list=$(parse_user_range "$users_range")
        while IFS= read -r line; do
            [[ -n "$line" ]] && users+=("$line")
        done <<< "$user_list"
    else
        local user_list
        user_list=$(discover_users "$USER_ENV_DIR")
        while IFS= read -r line; do
            [[ -n "$line" ]] && users+=("$line")
        done <<< "$user_list"
    fi
    
    if [[ ${#users[@]} -eq 0 ]]; then
        log_error "No users to process"
        exit 1
    fi
    
    if [[ -z "$test_email" ]]; then
        log_info "Preparing to send emails to ${#users[@]} users: ${users[*]}"
    fi
    
    # Send emails
    if send_user_emails "$verbose" "$dry_run" "$test_email" "$custom_subject" "${users[@]}"; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"