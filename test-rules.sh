#!/bin/bash

###############################################################################
# Test script for WordPress Manager rules
# Test XML-RPC block and WP-Login block
###############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get domain from user
if [ -z "$1" ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 example.com"
    exit 1
fi

DOMAIN="$1"
BASE_URL="http://${DOMAIN}"

print_info "Testing rules for domain: $DOMAIN"
echo ""

###############################################################################
# Test 1: Check .htaccess file directly
###############################################################################

print_info "Test 1: Check .htaccess file"
echo "----------------------------------------"

# Find .htaccess file
HTACCESS_FILE=""
for user_dir in /home/*; do
    if [ -d "$user_dir" ]; then
        test_file="$user_dir/domains/${DOMAIN}/public_html/.htaccess"
        if [ -f "$test_file" ]; then
            HTACCESS_FILE="$test_file"
            break
        fi
    fi
done

if [ -z "$HTACCESS_FILE" ]; then
    print_error ".htaccess file not found for domain: $DOMAIN"
    print_info "Searched in: /home/*/domains/${DOMAIN}/public_html/.htaccess"
else
    print_success "Found .htaccess: $HTACCESS_FILE"
    
    # Check XML-RPC block
    if grep -q "# BEGIN XML-RPC Block - WordPress Manager" "$HTACCESS_FILE" 2>/dev/null; then
        print_success "XML-RPC Block rule found in .htaccess"
    else
        print_error "XML-RPC Block rule NOT found in .htaccess"
    fi
    
    # Check WP-Login block
    if grep -q "# BEGIN WP-Login Block - WordPress Manager" "$HTACCESS_FILE" 2>/dev/null; then
        print_success "WP-Login Block rule found in .htaccess"
    else
        print_error "WP-Login Block rule NOT found in .htaccess"
    fi
fi

echo ""

###############################################################################
# Test 2: XML-RPC Block (HTTP test)
###############################################################################

print_info "Test 2: XML-RPC Block (xmlrpc.php) - HTTP Test"
echo "----------------------------------------"

XMLRPC_URL="${BASE_URL}/xmlrpc.php"

# Try curl first
if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$XMLRPC_URL" 2>/dev/null)
    
    if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" == "000" ]; then
        print_warning "curl failed to connect, trying wget..."
        # Try wget
        if command -v wget &> /dev/null; then
            HTTP_CODE=$(wget --spider --server-response --timeout=5 "$XMLRPC_URL" 2>&1 | grep -i "HTTP/" | tail -1 | awk '{print $2}')
        fi
    fi
    
    if [ "$HTTP_CODE" == "403" ] || [ "$HTTP_CODE" == "404" ]; then
        print_success "XML-RPC is blocked (HTTP $HTTP_CODE)"
    elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
        print_error "XML-RPC is NOT blocked (HTTP $HTTP_CODE)"
        print_warning "Expected: 403 or 404, Got: $HTTP_CODE"
    else
        print_warning "Cannot test HTTP connection (curl/wget failed)"
        print_info "This might be normal if testing from server itself"
        print_info "Try testing from external machine or browser"
    fi
else
    print_warning "curl not found, skipping HTTP test"
    print_info "Install curl: yum install curl (CentOS) or apt-get install curl (Ubuntu)"
fi

echo ""

###############################################################################
# Test 3: WP-Login Block (HTTP test)
###############################################################################

print_info "Test 3: WP-Login Block (wp-login.php) - HTTP Test"
echo "----------------------------------------"

# Get current IP
CURRENT_IP=""
if command -v curl &> /dev/null; then
    CURRENT_IP=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || curl -s --connect-timeout 3 ipinfo.io/ip 2>/dev/null)
fi

if [ -n "$CURRENT_IP" ]; then
    print_info "Your current IP: $CURRENT_IP"
    print_info "Note: If this is a Vietnam IP, wp-login.php should be accessible"
else
    print_warning "Could not determine your IP address"
fi

WPLOGIN_URL="${BASE_URL}/wp-login.php"

# Try curl first
if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$WPLOGIN_URL" 2>/dev/null)
    
    if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" == "000" ]; then
        print_warning "curl failed to connect, trying wget..."
        # Try wget
        if command -v wget &> /dev/null; then
            HTTP_CODE=$(wget --spider --server-response --timeout=5 "$WPLOGIN_URL" 2>&1 | grep -i "HTTP/" | tail -1 | awk '{print $2}')
        fi
    fi
    
    if [ "$HTTP_CODE" == "200" ]; then
        print_success "WP-Login accessible (HTTP $HTTP_CODE) - Your IP is allowed"
        print_warning "If you're testing from Vietnam IP, this is correct"
        print_warning "If you're testing from outside Vietnam, rules may not be working"
    elif [ "$HTTP_CODE" == "403" ]; then
        print_success "WP-Login is blocked (HTTP $HTTP_CODE) - Your IP is denied"
        print_warning "If you're testing from outside Vietnam, this is correct"
        print_warning "If you're testing from Vietnam IP, check your IP range"
    elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
        print_warning "Unexpected response (HTTP $HTTP_CODE)"
    else
        print_warning "Cannot test HTTP connection (curl/wget failed)"
        print_info "This might be normal if testing from server itself"
        print_info "Try testing from external machine or browser"
    fi
else
    print_warning "curl not found, skipping HTTP test"
fi

echo ""

###############################################################################
# Test 4: Show .htaccess rules content
###############################################################################

print_info "Test 4: Show .htaccess rules content"
echo "----------------------------------------"

if [ -n "$HTACCESS_FILE" ] && [ -f "$HTACCESS_FILE" ]; then
    print_info "XML-RPC Block section:"
    echo ""
    grep -A 10 "# BEGIN XML-RPC Block" "$HTACCESS_FILE" 2>/dev/null | head -12
    echo ""
    
    print_info "WP-Login Block section (first 20 lines):"
    echo ""
    grep -A 20 "# BEGIN WP-Login Block" "$HTACCESS_FILE" 2>/dev/null | head -22
    echo ""
else
    print_warning "Cannot display .htaccess content (file not found)"
fi

echo ""

###############################################################################
# Test 5: Manual Testing Instructions
###############################################################################

print_info "Test 5: Manual Testing Instructions"
echo "----------------------------------------"
echo ""
echo "To fully test WP-Login block:"
echo ""
echo "1. Test from Vietnam IP:"
echo "   - Should be able to access: ${BASE_URL}/wp-login.php"
echo "   - Should see login page (HTTP 200)"
echo ""
echo "2. Test from outside Vietnam:"
echo "   - Use VPN or proxy from another country"
echo "   - Try to access: ${BASE_URL}/wp-login.php"
echo "   - Should be blocked (HTTP 403 Forbidden)"
echo ""
echo "3. Test XML-RPC:"
echo "   - From any IP: ${BASE_URL}/xmlrpc.php"
echo "   - Should be blocked (HTTP 403 or 404)"
echo ""

###############################################################################
# Summary
###############################################################################

echo "=========================================="
print_info "Test Summary"
echo "=========================================="
echo ""
echo "Domain: $DOMAIN"
if [ -n "$HTACCESS_FILE" ]; then
    echo ".htaccess: $HTACCESS_FILE"
fi
echo "XML-RPC URL: ${BASE_URL}/xmlrpc.php"
echo "WP-Login URL: ${BASE_URL}/wp-login.php"
if [ -n "$CURRENT_IP" ]; then
    echo "Your IP: $CURRENT_IP"
fi
echo ""
print_info "Quick test commands:"
echo "  curl -I ${BASE_URL}/xmlrpc.php"
echo "  curl -I ${BASE_URL}/wp-login.php"
echo ""
print_info "Note: For accurate WP-Login test, use VPN/proxy from outside Vietnam"
echo ""

