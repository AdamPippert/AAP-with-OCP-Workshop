#!/bin/bash
#
# AAP Workshop Admin Page Builder
# Parses details.txt and generates a professional HTML page with lab access information
#
# Usage: ./build-admin-page.sh [options]
#
set -euo pipefail

# Default configuration
DEFAULT_INPUT_FILE="details.txt"
DEFAULT_OUTPUT_DIR="docs/html"
DEFAULT_OUTPUT_FILE="workshop-admin.html"

# Variables
INPUT_FILE="${DEFAULT_INPUT_FILE}"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
OUTPUT_FILE="${DEFAULT_OUTPUT_FILE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    cat << EOF
AAP Workshop Admin Page Builder

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -f, --file FILE     Input details file (default: ${DEFAULT_INPUT_FILE})
    -o, --output DIR    Output directory (default: ${DEFAULT_OUTPUT_DIR})
    -h, --help          Show this help message

EXAMPLES:
    $0                                      # Use defaults
    $0 -f custom-details.txt               # Custom input file
    $0 -o /tmp/workshop-html               # Custom output directory

DESCRIPTION:
    This script parses lab provisioning details from a text file and generates
    a professional HTML page with access information for workshop attendees.
    
    The generated page includes:
    - Lab environment credentials
    - OpenShift console access
    - Ansible Automation Platform URLs
    - SSH bastion information
    - AWS console access
    - Security warnings

SECURITY:
    ⚠️  The generated page contains sensitive credentials. Ensure:
    - Deploy only to trusted environments
    - Use appropriate access controls
    - Rotate credentials after workshop completion

EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                INPUT_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
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
}

# Validate environment
validate_environment() {
    log_info "Validating environment..."
    
    # Check if running from project root or scripts directory
    if [[ ! -f "${PROJECT_ROOT}/${INPUT_FILE}" && ! -f "${INPUT_FILE}" ]]; then
        log_error "Input file not found: ${INPUT_FILE}"
        log_error "Please ensure you're running from the project root or provide the correct path"
        exit 1
    fi
    
    # Use absolute path for input file
    if [[ -f "${PROJECT_ROOT}/${INPUT_FILE}" ]]; then
        INPUT_FILE="${PROJECT_ROOT}/${INPUT_FILE}"
    elif [[ -f "${INPUT_FILE}" ]]; then
        INPUT_FILE="$(realpath "${INPUT_FILE}")"
    fi
    
    # Create output directory if it doesn't exist
    OUTPUT_DIR="${PROJECT_ROOT}/${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}"
    
    log_success "Environment validation complete"
}

# Extract information from details.txt
extract_details() {
    log_info "Extracting lab details from: ${INPUT_FILE}"
    
    # Initialize variables
    AWS_ACCESS_KEY=""
    AWS_SECRET_KEY=""
    AWS_CONSOLE_URL=""
    AWS_CONSOLE_USER=""
    AWS_CONSOLE_PASS=""
    ROUTE53_DOMAIN=""
    SSH_COMMAND=""
    SSH_PASSWORD=""
    OPENSHIFT_CONSOLE=""
    OPENSHIFT_API=""
    OPENSHIFT_TOKEN=""
    OC_DOWNLOAD_URL=""
    AAP_URL=""
    AAP_USERNAME=""
    AAP_PASSWORD=""
    
    # Function to extract value for a given key from the structured format
    extract_value() {
        local key="$1"
        awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            getline
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
        }' "${INPUT_FILE}"
    }
    
    # Extract credentials and URLs using the new structured format
    AAP_URL=$(extract_value "aap_controller_web_url")
    AAP_USERNAME=$(extract_value "aap_controller_admin_user")
    AAP_PASSWORD=$(extract_value "aap_controller_admin_password")
    AAP_TOKEN=$(extract_value "aap_controller_token")
    SSH_HOST=$(extract_value "bastion_public_hostname")
    SSH_PORT=$(extract_value "bastion_ssh_port")
    SSH_USER=$(extract_value "bastion_ssh_user_name")
    SSH_PASSWORD=$(extract_value "bastion_ssh_password")
    OPENSHIFT_CONSOLE=$(extract_value "openshift_console_url")
    OPENSHIFT_API=$(extract_value "openshift_api_url")
    OPENSHIFT_TOKEN=$(extract_value "openshift_bearer_token")
    OC_DOWNLOAD_URL=$(extract_value "openshift_client_download_url")
    CLUSTER_DOMAIN=$(extract_value "openshift_cluster_ingress_domain")
    WORKSHOP_GUID=$(extract_value "guid")
    KUBEADMIN_PASSWORD=$(extract_value "openshift_kubeadmin_password")
    
    # Build SSH command from components
    if [[ -n "${SSH_USER}" && -n "${SSH_HOST}" && -n "${SSH_PORT}" ]]; then
        SSH_COMMAND="${SSH_USER}@${SSH_HOST} -p ${SSH_PORT}"
    fi
    
    # Set route53 domain to cluster domain
    ROUTE53_DOMAIN="${CLUSTER_DOMAIN}"
    
    # AWS credentials are not available in new format
    AWS_ACCESS_KEY=""
    AWS_SECRET_KEY=""
    AWS_CONSOLE_URL=""
    AWS_CONSOLE_USER=""
    AWS_CONSOLE_PASS=""
    
    log_success "Lab details extracted successfully"
}

# Generate HTML page
generate_html() {
    log_info "Generating HTML admin page..."
    
    local output_path="${OUTPUT_DIR}/${OUTPUT_FILE}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S UTC')
    
    cat > "${output_path}" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AAP Workshop - Lab Environment Access</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            font-weight: 300;
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .content {
            padding: 40px;
        }
        
        .security-warning {
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            border-left: 4px solid #f39c12;
            padding: 20px;
            margin-bottom: 30px;
            border-radius: 4px;
        }
        
        .security-warning h3 {
            color: #d68910;
            margin-bottom: 10px;
            display: flex;
            align-items: center;
        }
        
        .security-warning h3::before {
            content: "⚠️";
            margin-right: 10px;
            font-size: 1.2em;
        }
        
        .info-section {
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 8px;
            padding: 25px;
            margin-bottom: 25px;
        }
        
        .info-section h2 {
            color: #2c3e50;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #3498db;
        }
        
        .credential-group {
            background: white;
            border: 1px solid #dee2e6;
            border-radius: 6px;
            padding: 15px;
            margin-bottom: 15px;
        }
        
        .credential-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 0;
            border-bottom: 1px solid #f1f3f4;
        }
        
        .credential-item:last-child {
            border-bottom: none;
        }
        
        .credential-label {
            font-weight: 600;
            color: #495057;
            min-width: 150px;
        }
        
        .credential-value {
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            background: #f8f9fa;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 0.9em;
            word-break: break-all;
            flex: 1;
            margin-left: 15px;
            border: 1px solid #e9ecef;
        }
        
        .url-link {
            color: #3498db;
            text-decoration: none;
            font-weight: 500;
        }
        
        .url-link:hover {
            text-decoration: underline;
            color: #2980b9;
        }
        
        .copy-btn {
            background: #3498db;
            color: white;
            border: none;
            padding: 4px 8px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.8em;
            margin-left: 8px;
            transition: background 0.2s;
        }
        
        .copy-btn:hover {
            background: #2980b9;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
            gap: 25px;
            margin-top: 20px;
        }
        
        .footer {
            background: #2c3e50;
            color: white;
            padding: 20px 40px;
            text-align: center;
            font-size: 0.9em;
        }
        
        .timestamp {
            opacity: 0.7;
            font-style: italic;
        }
        
        @media (max-width: 768px) {
            .container {
                margin: 10px;
                border-radius: 8px;
            }
            
            .content {
                padding: 20px;
            }
            
            .header {
                padding: 20px;
            }
            
            .header h1 {
                font-size: 2em;
            }
            
            .grid {
                grid-template-columns: 1fr;
            }
            
            .credential-item {
                flex-direction: column;
                align-items: stretch;
            }
            
            .credential-value {
                margin-left: 0;
                margin-top: 5px;
            }
        }
        
        .status-indicator {
            display: inline-block;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #27ae60;
            margin-right: 8px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Advanced Ansible Automation Platform Workshop</h1>
            <p>Lab Environment Access Information</p>
        </div>
        
        <div class="content">
            <div class="security-warning">
                <h3>Security Notice</h3>
                <ul>
                    <li><strong>Keep credentials secure:</strong> Do not share these credentials outside of the workshop</li>
                    <li><strong>Workshop use only:</strong> These credentials are valid only during the workshop period</li>
                    <li><strong>No screenshots:</strong> Avoid taking screenshots that include sensitive information</li>
                    <li><strong>Report issues:</strong> Contact workshop facilitators immediately if you suspect credential compromise</li>
                </ul>
            </div>
            
            <div class="grid">
EOF

    # Add OpenShift section if data exists
    if [[ -n "${OPENSHIFT_CONSOLE}" ]]; then
        cat >> "${output_path}" << EOF
                <div class="info-section">
                    <h2><span class="status-indicator"></span>OpenShift Cluster Access</h2>
                    <div class="credential-group">
                        <div class="credential-item">
                            <span class="credential-label">Console URL:</span>
                            <span class="credential-value">
                                <a href="${OPENSHIFT_CONSOLE}" target="_blank" class="url-link">${OPENSHIFT_CONSOLE}</a>
                            </span>
                        </div>
EOF
        if [[ -n "${OPENSHIFT_API}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">API Endpoint:</span>
                            <span class="credential-value">${OPENSHIFT_API}</span>
                        </div>
EOF
        fi
        if [[ -n "${OPENSHIFT_TOKEN}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">Bearer Token:</span>
                            <span class="credential-value">${OPENSHIFT_TOKEN}</span>
                        </div>
EOF
        fi
        if [[ -n "${OC_DOWNLOAD_URL}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">oc Client:</span>
                            <span class="credential-value">
                                <a href="${OC_DOWNLOAD_URL}" target="_blank" class="url-link">Download oc client</a>
                            </span>
                        </div>
EOF
        fi
        cat >> "${output_path}" << EOF
                    </div>
                    <p><strong>Login Instructions:</strong></p>
EOF
        if [[ -n "${OPENSHIFT_TOKEN}" ]]; then
            cat >> "${output_path}" << 'EOF'
                    <p><strong>Option 1: Command Line (oc CLI):</strong></p>
                    <ol>
                        <li>Download and install the oc client</li>
                        <li>Run: <code>oc login [API-Endpoint] --token=[Bearer-Token]</code></li>
                        <li>Verify login: <code>oc whoami</code></li>
                    </ol>
                    <p><strong>Option 2: Web Console:</strong></p>
                    <ol>
                        <li>Click the Console URL above</li>
                        <li>Select your authentication method</li>
                        <li>Use your provided workshop credentials or bearer token</li>
                    </ol>
EOF
        else
            cat >> "${output_path}" << 'EOF'
                    <ol>
                        <li>Click the Console URL above</li>
                        <li>Select your authentication method</li>
                        <li>Use your provided workshop credentials</li>
                    </ol>
EOF
        fi
        cat >> "${output_path}" << 'EOF'
                </div>
EOF
    fi

    # Add AAP section if data exists
    if [[ -n "${AAP_URL}" ]]; then
        cat >> "${output_path}" << EOF
                <div class="info-section">
                    <h2><span class="status-indicator"></span>Ansible Automation Platform</h2>
                    <div class="credential-group">
                        <div class="credential-item">
                            <span class="credential-label">Controller URL:</span>
                            <span class="credential-value">
                                <a href="${AAP_URL}" target="_blank" class="url-link">${AAP_URL}</a>
                            </span>
                        </div>
EOF
        if [[ -n "${AAP_USERNAME}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">Username:</span>
                            <span class="credential-value">${AAP_USERNAME}</span>
                        </div>
EOF
        fi
        if [[ -n "${AAP_PASSWORD}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">Password:</span>
                            <span class="credential-value">${AAP_PASSWORD}</span>
                        </div>
EOF
        fi
        if [[ -n "${AAP_TOKEN}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">API Token:</span>
                            <span class="credential-value">${AAP_TOKEN}</span>
                        </div>
EOF
        fi
        cat >> "${output_path}" << 'EOF'
                    </div>
                    <p><strong>Access Instructions:</strong></p>
                    <ol>
                        <li>Navigate to the Controller URL</li>
                        <li>Log in with the provided credentials</li>
                        <li>Explore the AAP interface and configured resources</li>
                    </ol>
                </div>
EOF
    fi

    # Add SSH section if data exists
    if [[ -n "${SSH_COMMAND}" ]]; then
        cat >> "${output_path}" << EOF
                <div class="info-section">
                    <h2><span class="status-indicator"></span>SSH Bastion Access</h2>
                    <div class="credential-group">
                        <div class="credential-item">
                            <span class="credential-label">SSH Command:</span>
                            <span class="credential-value">ssh ${SSH_COMMAND}</span>
                        </div>
EOF
        if [[ -n "${SSH_PASSWORD}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">Password:</span>
                            <span class="credential-value">${SSH_PASSWORD}</span>
                        </div>
EOF
        fi
        cat >> "${output_path}" << 'EOF'
                    </div>
                    <p><strong>Connection Instructions:</strong></p>
                    <ol>
                        <li>Open a terminal or SSH client</li>
                        <li>Copy and paste the SSH command above</li>
                        <li>Enter the password when prompted</li>
                        <li>You'll have access to the lab environment CLI tools</li>
                    </ol>
                </div>
EOF
    fi

    # Add AWS section if data exists
    if [[ -n "${AWS_CONSOLE_URL}" ]]; then
        cat >> "${output_path}" << EOF
                <div class="info-section">
                    <h2><span class="status-indicator"></span>AWS Console Access</h2>
                    <div class="credential-group">
                        <div class="credential-item">
                            <span class="credential-label">Console URL:</span>
                            <span class="credential-value">
                                <a href="${AWS_CONSOLE_URL}" target="_blank" class="url-link">${AWS_CONSOLE_URL}</a>
                            </span>
                        </div>
EOF
        if [[ -n "${AWS_CONSOLE_USER}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">Username:</span>
                            <span class="credential-value">${AWS_CONSOLE_USER}</span>
                        </div>
EOF
        fi
        if [[ -n "${AWS_CONSOLE_PASS}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">Password:</span>
                            <span class="credential-value">${AWS_CONSOLE_PASS}</span>
                        </div>
EOF
        fi
        if [[ -n "${ROUTE53_DOMAIN}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">Route53 Domain:</span>
                            <span class="credential-value">${ROUTE53_DOMAIN}</span>
                        </div>
EOF
        fi
        cat >> "${output_path}" << 'EOF'
                    </div>
                    <p><strong>Note:</strong> AWS access is provided for advanced scenarios and infrastructure inspection.</p>
                </div>
EOF
    fi

    # Add API credentials section if they exist
    if [[ -n "${AWS_ACCESS_KEY}" ]]; then
        cat >> "${output_path}" << EOF
                <div class="info-section">
                    <h2><span class="status-indicator"></span>AWS API Credentials</h2>
                    <div class="credential-group">
                        <div class="credential-item">
                            <span class="credential-label">Access Key:</span>
                            <span class="credential-value">${AWS_ACCESS_KEY}</span>
                        </div>
EOF
        if [[ -n "${AWS_SECRET_KEY}" ]]; then
            cat >> "${output_path}" << EOF
                        <div class="credential-item">
                            <span class="credential-label">Secret Key:</span>
                            <span class="credential-value">${AWS_SECRET_KEY}</span>
                        </div>
EOF
        fi
        cat >> "${output_path}" << 'EOF'
                    </div>
                    <div class="security-warning">
                        <h3>⚠️ Critical Security Warning</h3>
                        <p><strong>NEVER</strong> expose these AWS credentials in:</p>
                        <ul>
                            <li>Git repositories or version control</li>
                            <li>Public forums or chat channels</li>
                            <li>Screenshots or documentation</li>
                            <li>Shared files or cloud storage</li>
                        </ul>
                        <p>Credential exposure will result in immediate environment termination.</p>
                    </div>
                </div>
EOF
    fi

    # Close the HTML structure
    cat >> "${output_path}" << EOF
            </div>
            
            <div class="info-section">
                <h2>Workshop Resources</h2>
                <div class="credential-group">
                    <div class="credential-item">
                        <span class="credential-label">Module Guides:</span>
                        <span class="credential-value">
                            <a href="module1-workshop-guide.html" class="url-link">Module 1: Dynamic Inventory</a> |
                            <a href="module2-workshop-guide.html" class="url-link">Module 2: RBAC & Deployment</a> |
                            <a href="module3-workshop-guide.html" class="url-link">Module 3: Advanced Automation</a>
                        </span>
                    </div>
                    <div class="credential-item">
                        <span class="credential-label">Support:</span>
                        <span class="credential-value">Contact workshop facilitators for technical assistance</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p>Generated on: <span class="timestamp">${timestamp}</span></p>
            <p>AAP Workshop Lab Environment - For Workshop Use Only</p>
        </div>
    </div>
    
    <script>
        // Add copy functionality
        document.querySelectorAll('.credential-value').forEach(function(element) {
            if (element.textContent.trim() && !element.querySelector('a')) {
                const copyBtn = document.createElement('button');
                copyBtn.className = 'copy-btn';
                copyBtn.textContent = 'Copy';
                copyBtn.onclick = function() {
                    navigator.clipboard.writeText(element.textContent.trim()).then(function() {
                        copyBtn.textContent = 'Copied!';
                        setTimeout(function() {
                            copyBtn.textContent = 'Copy';
                        }, 2000);
                    });
                };
                element.appendChild(copyBtn);
            }
        });
        
        // Add warning before external links
        document.querySelectorAll('a[target="_blank"]').forEach(function(link) {
            link.onclick = function(e) {
                if (!confirm('You are about to open an external link. Ensure you are in a secure environment. Continue?')) {
                    e.preventDefault();
                }
            };
        });
    </script>
</body>
</html>
EOF

    log_success "HTML admin page generated: ${output_path}"
}

# Validate generated HTML
validate_html() {
    local output_path="${OUTPUT_DIR}/${OUTPUT_FILE}"
    
    log_info "Validating generated HTML..."
    
    if [[ ! -f "${output_path}" ]]; then
        log_error "Generated HTML file not found: ${output_path}"
        exit 1
    fi
    
    # Basic HTML validation
    if ! grep -q "<!DOCTYPE html>" "${output_path}"; then
        log_error "Invalid HTML: Missing DOCTYPE declaration"
        exit 1
    fi
    
    if ! grep -q "</html>" "${output_path}"; then
        log_error "Invalid HTML: Missing closing html tag"
        exit 1
    fi
    
    local file_size=$(stat -c%s "${output_path}" 2>/dev/null || stat -f%z "${output_path}" 2>/dev/null || echo "unknown")
    log_success "HTML validation complete (size: ${file_size} bytes)"
}

# Main execution
main() {
    echo "AAP Workshop Admin Page Builder"
    echo "==============================="
    echo
    
    parse_args "$@"
    validate_environment
    extract_details
    generate_html
    validate_html
    
    echo
    log_success "Admin page generation complete!"
    echo
    echo "Generated file: ${OUTPUT_DIR}/${OUTPUT_FILE}"
    echo "View locally:   file://${OUTPUT_DIR}/${OUTPUT_FILE}"
    echo
    echo "Next steps:"
    echo "1. Review the generated page in your browser"
    echo "2. Deploy to OpenShift: ./scripts/deploy-admin-page.sh"
    echo "3. Share the deployed URL with workshop attendees"
    echo
}

# Execute main function
main "$@"