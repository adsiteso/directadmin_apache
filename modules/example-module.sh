#!/bin/bash

###############################################################################
# Example Module Template
# Copy this file and modify to create a new module
###############################################################################

# Module name (must match filename without .sh)
MODULE_NAME="example-module"

###############################################################################
# Module Functions (REQUIRED)
###############################################################################

# Description shown in main menu (REQUIRED)
example-module_description() {
    echo "Example Module - Template for new modules"
}

# Enable module functionality (REQUIRED)
example-module_enable() {
    print_info "Enabling example-module..."
    
    # Your enable code here
    # Example: modify files, add configurations, etc.
    
    local count=0
    local failed=0
    
    # Example: iterate through WordPress sites
    while IFS=: read -r domain docroot; do
        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi
        
        # Your code here
        # Example: modify .htaccess, wp-config.php, etc.
        
        if [ $? -eq 0 ]; then
            print_success "Updated $domain"
            ((count++))
        else
            print_error "Failed to update $domain"
            ((failed++))
        fi
        
    done < <(get_wordpress_sites)
    
    echo ""
    print_info "Summary: $count sites updated, $failed failed"
    
    if [ $failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Disable module functionality (REQUIRED)
example-module_disable() {
    print_info "Disabling example-module..."
    
    # Your disable code here
    # Example: remove modifications, restore original state
    
    local count=0
    local failed=0
    
    # Example: iterate through WordPress sites
    while IFS=: read -r domain docroot; do
        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi
        
        # Your code here
        # Example: remove rules from .htaccess, etc.
        
        if [ $? -eq 0 ]; then
            print_success "Reverted $domain"
            ((count++))
        else
            print_error "Failed to revert $domain"
            ((failed++))
        fi
        
    done < <(get_wordpress_sites)
    
    echo ""
    print_info "Summary: $count sites updated, $failed failed"
    
    if [ $failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Check module status (REQUIRED)
example-module_status() {
    print_info "Checking example-module status..."
    echo ""
    
    local total=0
    local enabled=0
    local disabled=0
    
    # Example: check status for each site
    while IFS=: read -r domain docroot; do
        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi
        
        ((total++))
        
        # Your status check code here
        # Example: check if rule exists in .htaccess
        local status_file="$docroot/.example-status"
        
        if [ -f "$status_file" ]; then
            echo -e "  ${GREEN}âœ“${NC} $domain - Enabled"
            ((enabled++))
        else
            echo -e "  ${RED}âœ—${NC} $domain - Disabled"
            ((disabled++))
        fi
        
    done < <(get_wordpress_sites)
    
    echo ""
    echo "Summary:"
    echo "  Total WordPress sites: $total"
    echo -e "  ${GREEN}Enabled: $enabled${NC}"
    echo -e "  ${RED}Disabled: $disabled${NC}"
}

###############################################################################
# Available Utility Functions from Main Script:
#
# - print_info "message"      - Print info message
# - print_success "message"    - Print success message
# - print_warning "message"    - Print warning message
# - print_error "message"      - Print error message
# - get_wordpress_sites        - Get list of WordPress sites (format: domain:docroot)
# - count_wordpress_sites      - Count total WordPress sites
#
# DirectAdmin paths:
# - DA_USERDATA="/usr/local/directadmin/data/users"
# - DA_HTTPD_CONF="/etc/httpd/conf/extra/httpd-includes.conf"
#
###############################################################################

