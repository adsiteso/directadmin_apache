#!/bin/bash

###############################################################################
# WP-Login Block Module
# Block wp-login.php access except for Vietnam IP addresses
###############################################################################

# Module name
MODULE_NAME="wp-login-block"

###############################################################################
# Module Functions
###############################################################################

wp-login-block_description() {
    echo "Block WP-Login (Only Vietnam IP)"
}

# Enable WP-Login blocking (only Vietnam IP allowed)
wp-login-block_enable() {
    print_info "Enabling WP-Login blocking (only Vietnam IP allowed) for all WordPress sites..."
    
    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        return 1
    fi
    
    local count=0
    local failed=0
    
    # Get all WordPress sites into array
    local sites_output
    sites_output=$(get_wordpress_sites 2>&1)
    local sites=()
    
    if [ -n "$sites_output" ]; then
        while IFS= read -r site; do
            if [ -n "$site" ]; then
                sites+=("$site")
            fi
        done <<< "$sites_output"
    fi
    
    if [ ${#sites[@]} -eq 0 ]; then
        print_warning "No WordPress sites found"
        return 0
    fi
    
    print_info "Found ${#sites[@]} WordPress site(s) to process"
    
    # Process each site
    for site in "${sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"
        
        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi
        
        local htaccess_file="$docroot/.htaccess"
        
        # Create .htaccess if it doesn't exist
        if [ ! -f "$htaccess_file" ]; then
            touch "$htaccess_file"
            chown webapps:webapps "$htaccess_file" 2>/dev/null || true
        fi
        
        # Check if rule already exists
        if grep -q "# BEGIN WP-Login Block - WordPress Manager" "$htaccess_file" 2>/dev/null; then
            print_warning "WP-Login block already exists for $domain"
            continue
        fi
        
        # Add blocking rules
        {
            echo ""
            echo "# BEGIN WP-Login Block - WordPress Manager"
            echo "# Added on $(date '+%Y-%m-%d %H:%M:%S')"
            echo "# Block wp-login.php, only allow Vietnam IP addresses"
            echo "<Files \"wp-login.php\">"
            echo "    # Custom error message for blocked access"
            echo "    ErrorDocument 403 \"<html><head><title>Access Denied</title><style>body{font-family:Arial,sans-serif;text-align:center;padding:50px;background:#f5f5f5;}h1{color:#d32f2f;margin-bottom:20px;}p{color:#666;font-size:16px;line-height:1.6;max-width:600px;margin:0 auto;}hr{margin:30px auto;width:100px;border:none;border-top:2px solid #ddd;}</style></head><body><h1>403 - Access Denied</h1><hr><p><strong>WordPress Login Access Restricted</strong></p><p>Access to wp-login.php is restricted to Vietnam IP addresses only for security purposes.</p><p>If you believe this is an error, please contact the website administrator.</p></body></html>\""
            echo "    <RequireAny>"
            echo "        Require ip 14.0.0.0/8"
            echo "        Require ip 27.0.0.0/8"
            echo "        Require ip 42.0.0.0/8"
            echo "        Require ip 49.0.0.0/8"
            echo "        Require ip 58.0.0.0/8"
            echo "        Require ip 59.0.0.0/8"
            echo "        Require ip 60.0.0.0/8"
            echo "        Require ip 61.0.0.0/8"
            echo "        Require ip 101.0.0.0/8"
            echo "        Require ip 103.0.0.0/8"
            echo "        Require ip 106.0.0.0/8"
            echo "        Require ip 110.0.0.0/8"
            echo "        Require ip 111.0.0.0/8"
            echo "        Require ip 112.0.0.0/8"
            echo "        Require ip 113.0.0.0/8"
            echo "        Require ip 114.0.0.0/8"
            echo "        Require ip 115.0.0.0/8"
            echo "        Require ip 116.0.0.0/8"
            echo "        Require ip 117.0.0.0/8"
            echo "        Require ip 118.0.0.0/8"
            echo "        Require ip 119.0.0.0/8"
            echo "        Require ip 120.0.0.0/8"
            echo "        Require ip 121.0.0.0/8"
            echo "        Require ip 122.0.0.0/8"
            echo "        Require ip 123.0.0.0/8"
            echo "        Require ip 124.0.0.0/8"
            echo "        Require ip 125.0.0.0/8"
            echo "        Require ip 126.0.0.0/8"
            echo "        Require ip 171.224.0.0/13"
            echo "        Require ip 175.224.0.0/13"
            echo "        Require ip 180.0.0.0/8"
            echo "        Require ip 183.0.0.0/8"
            echo "        Require ip 202.0.0.0/7"
            echo "        Require ip 203.0.0.0/8"
            echo "        Require ip 210.0.0.0/7"
            echo "        Require ip 211.0.0.0/8"
            echo "        Require ip 218.0.0.0/7"
            echo "        Require ip 219.0.0.0/8"
            echo "        Require ip 220.0.0.0/7"
            echo "        Require ip 221.0.0.0/8"
            echo "        Require ip 222.0.0.0/7"
            echo "        Require ip 223.0.0.0/8"
            echo "    </RequireAny>"
            echo "</Files>"
            echo ""
            echo "# END WP-Login Block - WordPress Manager"
        } >> "$htaccess_file"
        
        if [ $? -eq 0 ]; then
            print_success "Blocked WP-Login (VN IP only) for $domain"
            ((count++))
        else
            print_error "Failed to block WP-Login for $domain"
            ((failed++))
        fi
        
    done
    
    echo ""
    print_info "Summary: $count sites updated, $failed failed"
    
    if [ $failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Disable WP-Login blocking
wp-login-block_disable() {
    print_info "Disabling WP-Login blocking for all WordPress sites..."
    
    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        return 1
    fi
    
    local count=0
    local failed=0
    
    # Get all WordPress sites into array
    local sites_output
    sites_output=$(get_wordpress_sites 2>&1)
    local sites=()
    
    if [ -n "$sites_output" ]; then
        while IFS= read -r site; do
            if [ -n "$site" ]; then
                sites+=("$site")
            fi
        done <<< "$sites_output"
    fi
    
    if [ ${#sites[@]} -eq 0 ]; then
        print_warning "No WordPress sites found"
        return 0
    fi
    
    print_info "Found ${#sites[@]} WordPress site(s) to process"
    
    # Process each site
    for site in "${sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"
        
        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi
        
        local htaccess_file="$docroot/.htaccess"
        
        if [ ! -f "$htaccess_file" ]; then
            continue
        fi
        
        # Check if rule exists
        if ! grep -q "# BEGIN WP-Login Block - WordPress Manager" "$htaccess_file" 2>/dev/null; then
            continue
        fi
        
        # Remove blocking rules using sed
        # Remove from "# BEGIN WP-Login Block" to "# END WP-Login Block" including blank lines
        sed -i '/^# BEGIN WP-Login Block - WordPress Manager/,/^# END WP-Login Block - WordPress Manager$/d' "$htaccess_file" 2>/dev/null
        # Remove multiple consecutive blank lines
        sed -i '/^$/N;/^\n$/d' "$htaccess_file" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            print_success "Unblocked WP-Login for $domain"
            ((count++))
        else
            print_error "Failed to unblock WP-Login for $domain"
            ((failed++))
        fi
        
    done
    
    echo ""
    print_info "Summary: $count sites updated, $failed failed"
    
    if [ $failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Check status of WP-Login blocking
wp-login-block_status() {
    print_info "Checking WP-Login block status for all WordPress sites..."
    echo ""
    
    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        return 1
    fi
    
    local total=0
    local blocked=0
    local unblocked=0
    
    # Get all WordPress sites into array
    local sites_output
    sites_output=$(get_wordpress_sites 2>&1)
    local sites=()
    
    if [ -n "$sites_output" ]; then
        while IFS= read -r site; do
            if [ -n "$site" ]; then
                sites+=("$site")
            fi
        done <<< "$sites_output"
    fi
    
    if [ ${#sites[@]} -eq 0 ]; then
        print_warning "No WordPress sites found"
        echo ""
        echo "Summary:"
        echo "  Total WordPress sites: 0"
        echo -e "  ${GREEN}Blocked: 0${NC}"
        echo -e "  ${RED}Not blocked: 0${NC}"
        return 0
    fi
    
    print_info "Found ${#sites[@]} WordPress site(s)"
    echo ""
    
    # Process each site
    for site in "${sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"
        
        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi
        
        local htaccess_file="$docroot/.htaccess"
        ((total++))
        
        if [ -f "$htaccess_file" ] && grep -q "# BEGIN WP-Login Block - WordPress Manager" "$htaccess_file" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $domain - Blocked (VN IP only)"
            ((blocked++))
        else
            echo -e "  ${RED}✗${NC} $domain - Not blocked"
            ((unblocked++))
        fi
        
    done
    
    echo ""
    echo "Summary:"
    echo "  Total WordPress sites: $total"
    echo -e "  ${GREEN}Blocked (VN IP only): $blocked${NC}"
    echo -e "  ${RED}Not blocked: $unblocked${NC}"
}

###############################################################################
# Note: This module uses utility functions from main script
# Functions like print_info, print_success, get_wordpress_sites are available
# from the main script when this module is loaded via 'source'
###############################################################################

