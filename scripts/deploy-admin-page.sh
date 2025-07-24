#!/bin/bash
#
# AAP Workshop Admin Page Deployment Script
# Deploys the generated admin page to OpenShift as a web service
#
# Usage: ./deploy-admin-page.sh [options]
#
set -euo pipefail

# Default configuration
DEFAULT_NAMESPACE="workshop-admin"
DEFAULT_PORT="8080"
DEFAULT_REPLICAS="2"
DEFAULT_HTML_FILE="docs/html/workshop-admin.html"

# Variables
NAMESPACE="${DEFAULT_NAMESPACE}"
PORT="${DEFAULT_PORT}"
REPLICAS="${DEFAULT_REPLICAS}"
HTML_FILE="${DEFAULT_HTML_FILE}"
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
AAP Workshop Admin Page Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -n, --namespace NS  Kubernetes namespace (default: ${DEFAULT_NAMESPACE})
    -p, --port PORT     Service port (default: ${DEFAULT_PORT})
    -r, --replicas N    Number of replicas (default: ${DEFAULT_REPLICAS})
    -f, --file FILE     HTML file to deploy (default: ${DEFAULT_HTML_FILE})
    -h, --help          Show this help message
    --cleanup           Remove deployed resources and exit

EXAMPLES:
    $0                                      # Deploy with defaults
    $0 -n lab-access                       # Custom namespace
    $0 -r 3 -p 8090                       # 3 replicas on port 8090
    $0 --cleanup                           # Remove all deployed resources

DESCRIPTION:
    This script deploys the generated admin page to OpenShift as a highly
    available web service accessible to workshop attendees.
    
    Deployment includes:
    - Dedicated namespace with proper RBAC
    - ConfigMap containing the HTML content
    - Nginx deployment serving static content
    - Service for internal cluster access
    - Route for external access with TLS

PREREQUISITES:
    - OpenShift cluster access with admin permissions
    - oc CLI configured and authenticated
    - Generated admin page (run build-admin-page.sh first)

SECURITY:
    ⚠️  The deployed page contains sensitive credentials:
    - Deploy only to trusted clusters
    - Monitor access logs
    - Clean up after workshop completion

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
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -r|--replicas)
                REPLICAS="$2"
                shift 2
                ;;
            -f|--file)
                HTML_FILE="$2"
                shift 2
                ;;
            --cleanup)
                cleanup_deployment
                exit 0
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

# Validate environment and prerequisites
validate_environment() {
    log_info "Validating deployment environment..."
    
    # Check oc CLI
    if ! command -v oc &> /dev/null; then
        log_error "oc CLI not found. Please install and configure the OpenShift CLI"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! oc whoami &> /dev/null; then
        log_error "Not authenticated to OpenShift cluster. Please run 'oc login'"
        exit 1
    fi
    
    # Check cluster admin permissions
    if ! oc auth can-i create namespaces &> /dev/null; then
        log_warning "Limited permissions detected. Some operations may require cluster-admin access"
    fi
    
    # Validate HTML file exists
    local html_path="${PROJECT_ROOT}/${HTML_FILE}"
    if [[ ! -f "${html_path}" ]]; then
        log_error "HTML file not found: ${html_path}"
        log_error "Please run ./scripts/build-admin-page.sh first"
        exit 1
    fi
    
    HTML_FILE="${html_path}"
    
    # Validate numeric parameters
    if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [[ "${PORT}" -lt 1 ]] || [[ "${PORT}" -gt 65535 ]]; then
        log_error "Invalid port number: ${PORT}"
        exit 1
    fi
    
    if ! [[ "${REPLICAS}" =~ ^[0-9]+$ ]] || [[ "${REPLICAS}" -lt 1 ]]; then
        log_error "Invalid replica count: ${REPLICAS}"
        exit 1
    fi
    
    log_success "Environment validation complete"
}

# Create namespace with proper configuration
create_namespace() {
    log_info "Creating namespace: ${NAMESPACE}"
    
    # Check if namespace already exists
    if oc get namespace "${NAMESPACE}" &> /dev/null; then
        log_warning "Namespace ${NAMESPACE} already exists, continuing..."
    else
        cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    name: ${NAMESPACE}
    purpose: workshop-admin
    security.openshift.io/security-context-constraints: restricted
  annotations:
    openshift.io/description: "AAP Workshop Administration Resources"
    openshift.io/display-name: "Workshop Admin"
EOF
        log_success "Namespace ${NAMESPACE} created"
    fi
}

# Create ConfigMap with HTML content
create_configmap() {
    log_info "Creating ConfigMap with admin page content..."
    
    # Create ConfigMap from HTML file
    oc create configmap workshop-admin-content \
        --from-file=index.html="${HTML_FILE}" \
        --namespace="${NAMESPACE}" \
        --dry-run=client -o yaml | oc apply -f -
    
    log_success "ConfigMap workshop-admin-content created/updated"
}

# Create Nginx deployment
create_deployment() {
    log_info "Creating deployment with ${REPLICAS} replicas..."
    
    cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workshop-admin
  namespace: ${NAMESPACE}
  labels:
    app: workshop-admin
    component: web-server
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app: workshop-admin
  template:
    metadata:
      labels:
        app: workshop-admin
        component: web-server
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
          name: http
        volumeMounts:
        - name: html-content
          mountPath: /usr/share/nginx/html
          readOnly: true
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          runAsUser: 1001
          capabilities:
            drop:
            - ALL
      volumes:
      - name: html-content
        configMap:
          name: workshop-admin-content
      - name: nginx-config
        configMap:
          name: workshop-admin-nginx-config
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: workshop-admin-nginx-config
  namespace: ${NAMESPACE}
data:
  default.conf: |
    server {
        listen 80;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html;
        
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        
        # Cache static content
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
            expires 1h;
            add_header Cache-Control "public, immutable";
        }
        
        # Main content
        location / {
            try_files \$uri \$uri/ /index.html;
            add_header Cache-Control "no-cache, no-store, must-revalidate";
        }
        
        # Security
        location ~ /\. {
            deny all;
        }
        
        # Health check
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
EOF
    
    log_success "Deployment workshop-admin created/updated"
}

# Create service
create_service() {
    log_info "Creating service on port ${PORT}..."
    
    cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: workshop-admin
  namespace: ${NAMESPACE}
  labels:
    app: workshop-admin
  annotations:
    description: "Workshop admin page service"
spec:
  selector:
    app: workshop-admin
  ports:
  - name: http
    port: ${PORT}
    targetPort: 80
    protocol: TCP
  type: ClusterIP
EOF
    
    log_success "Service workshop-admin created/updated"
}

# Create route for external access
create_route() {
    log_info "Creating external route..."
    
    cat << EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: workshop-admin
  namespace: ${NAMESPACE}
  labels:
    app: workshop-admin
  annotations:
    description: "External access to workshop admin page"
spec:
  to:
    kind: Service
    name: workshop-admin
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF
    
    log_success "Route workshop-admin created/updated"
}

# Wait for deployment to be ready
wait_for_ready() {
    log_info "Waiting for deployment to be ready..."
    
    # Wait for deployment to be available
    if oc rollout status deployment/workshop-admin -n "${NAMESPACE}" --timeout=300s; then
        log_success "Deployment is ready"
    else
        log_error "Deployment failed to become ready within timeout"
        log_info "Checking deployment status..."
        oc describe deployment workshop-admin -n "${NAMESPACE}"
        exit 1
    fi
    
    # Verify pods are running
    local ready_pods=$(oc get pods -l app=workshop-admin -n "${NAMESPACE}" --no-headers | grep Running | wc -l)
    log_info "Ready pods: ${ready_pods}/${REPLICAS}"
}

# Display deployment information
show_deployment_info() {
    log_info "Retrieving deployment information..."
    
    # Get route URL
    local route_url=""
    if route_url=$(oc get route workshop-admin -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null); then
        route_url="https://${route_url}"
    else
        log_warning "Could not retrieve route URL"
        route_url="[Route not found]"
    fi
    
    # Get service info
    local service_ip=""
    if service_ip=$(oc get service workshop-admin -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null); then
        service_ip="${service_ip}:${PORT}"
    else
        service_ip="[Service not found]"
    fi
    
    echo
    echo "======================================"
    echo "  DEPLOYMENT SUCCESSFUL"
    echo "======================================"
    echo
    echo "📋 Deployment Details:"
    echo "   Namespace:     ${NAMESPACE}"
    echo "   Replicas:      ${REPLICAS}"
    echo "   Service Port:  ${PORT}"
    echo
    echo "🌐 Access URLs:"
    echo "   External:      ${route_url}"
    echo "   Internal:      http://${service_ip}"
    echo
    echo "🔧 Management Commands:"
    echo "   View pods:     oc get pods -n ${NAMESPACE}"
    echo "   View logs:     oc logs deployment/workshop-admin -n ${NAMESPACE}"
    echo "   Scale:         oc scale deployment workshop-admin --replicas=N -n ${NAMESPACE}"
    echo "   Delete:        ./scripts/deploy-admin-page.sh --cleanup"
    echo
    echo "⚠️  Security Reminder:"
    echo "   - Monitor access to the admin page"
    echo "   - Clean up after workshop completion"
    echo "   - Rotate credentials regularly"
    echo
}

# Cleanup function
cleanup_deployment() {
    log_info "Cleaning up workshop admin deployment..."
    
    if oc get namespace "${NAMESPACE}" &> /dev/null; then
        log_info "Deleting namespace: ${NAMESPACE}"
        oc delete namespace "${NAMESPACE}" --ignore-not-found=true
        
        # Wait for namespace deletion
        local timeout=60
        local count=0
        while oc get namespace "${NAMESPACE}" &> /dev/null && [[ $count -lt $timeout ]]; do
            sleep 2
            count=$((count + 2))
            if [[ $((count % 10)) -eq 0 ]]; then
                log_info "Waiting for namespace deletion... (${count}s)"
            fi
        done
        
        if oc get namespace "${NAMESPACE}" &> /dev/null; then
            log_warning "Namespace deletion is taking longer than expected"
            log_info "You can check status with: oc get namespace ${NAMESPACE}"
        else
            log_success "Namespace ${NAMESPACE} deleted successfully"
        fi
    else
        log_info "Namespace ${NAMESPACE} not found, nothing to clean up"
    fi
    
    log_success "Cleanup complete"
}

# Verify deployment health
verify_deployment() {
    log_info "Verifying deployment health..."
    
    # Check if all pods are ready
    local ready_pods=$(oc get pods -l app=workshop-admin -n "${NAMESPACE}" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o True | wc -l)
    local total_pods=$(oc get pods -l app=workshop-admin -n "${NAMESPACE}" --no-headers | wc -l)
    
    if [[ "${ready_pods}" -eq "${REPLICAS}" ]]; then
        log_success "All ${REPLICAS} pods are ready"
    else
        log_warning "Only ${ready_pods}/${REPLICAS} pods are ready"
    fi
    
    # Test internal connectivity
    if oc get service workshop-admin -n "${NAMESPACE}" &> /dev/null; then
        log_success "Service is accessible"
    else
        log_error "Service is not accessible"
    fi
    
    # Test external route
    if oc get route workshop-admin -n "${NAMESPACE}" &> /dev/null; then
        log_success "External route is configured"
    else
        log_error "External route is not configured"
    fi
    
    log_success "Deployment verification complete"
}

# Main execution
main() {
    echo "AAP Workshop Admin Page Deployment"
    echo "=================================="
    echo
    
    parse_args "$@"
    validate_environment
    create_namespace
    create_configmap
    create_deployment
    create_service
    create_route
    wait_for_ready
    verify_deployment
    show_deployment_info
    
    echo "🎉 Deployment completed successfully!"
    echo
    echo "Share the external URL with workshop attendees."
    echo "Monitor the deployment and clean up after workshop completion."
    echo
}

# Handle script interruption
trap 'log_error "Script interrupted. Some resources may need manual cleanup."' INT TERM

# Execute main function
main "$@"