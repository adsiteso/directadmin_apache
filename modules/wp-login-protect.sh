#!/bin/bash

###############################################################################
# WP-Login Protect Module
# Add password protection to wp-login.php using HTTP Basic Authentication
###############################################################################

# Module name
MODULE_NAME="wp-login-protect"

# Default username and password (can be changed)
DEFAULT_USERNAME="wpadmin"
DEFAULT_PASSWORD=""

###############################################################################
# Module Functions
###############################################################################

wp-login-protect_description() {
    echo "Protect WP-Login (Password Protection)"
}

# Enable WP-Login password protection
wp-login-protect_enable() {
    print_info "Enabling password protection for wp-login.php on all WordPress sites..."
    
    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        return 1
    fi
    
    # Ask for username and password
    echo ""
    echo -n "Enter username for wp-login.php protection (default: $DEFAULT_USERNAME): "
    read username
    username="${username:-$DEFAULT_USERNAME}"
    
    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        return 1
    fi
    
    echo -n "Enter password for wp-login.php protection: "
    read -s password
    echo ""
    
    if [ -z "$password" ]; then
        print_error "Password cannot be empty"
        return 1
    fi
    
    # Confirm password
    echo -n "Confirm password: "
    read -s password_confirm
    echo ""
    
    if [ "$password" != "$password_confirm" ]; then
        print_error "Passwords do not match"
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
    
    # Check if htpasswd command exists
    if ! command -v htpasswd &> /dev/null; then
        print_error "htpasswd command not found. Please install apache2-utils or httpd-tools"
        return 1
    fi
    
    # Process each site
    for site in "${sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"
        
        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi
        
        local htaccess_file="$docroot/.htaccess"
        local htpasswd_file="$docroot/.htpasswd"
        
        # Create .htaccess if it doesn't exist
        if [ ! -f "$htaccess_file" ]; then
            touch "$htaccess_file"
            chown webapps:webapps "$htaccess_file" 2>/dev/null || true
        fi
        
        # Check if rule already exists (match with or without date, old or new name)
        if grep -q "# BEGIN WP-Login Protect - WordPress Manager" "$htaccess_file" 2>/dev/null || \
           grep -q "# BEGIN WP-Login Block - WordPress Manager" "$htaccess_file" 2>/dev/null; then
            print_warning "WP-Login protection already exists for $domain, updating password..."
            # Remove old password protection block (both old and new names)
            sed -i '/^# BEGIN WP-Login Protect - WordPress Manager/,/^# END WP-Login Protect - WordPress Manager$/d' "$htaccess_file" 2>/dev/null
            sed -i '/^# BEGIN WP-Login Block - WordPress Manager/,/^# END WP-Login Block - WordPress Manager$/d' "$htaccess_file" 2>/dev/null
        fi
        
        # Create or update .htpasswd file
        if [ -f "$htpasswd_file" ]; then
            # Update existing user or create new
            echo "$password" | htpasswd -i "$htpasswd_file" "$username" 2>/dev/null
        else
            # Create new .htpasswd file
            echo "$password" | htpasswd -ci "$htpasswd_file" "$username" 2>/dev/null
        fi
        
        if [ $? -ne 0 ]; then
            print_error "Failed to create password file for $domain"
            ((failed++))
            continue
        fi
        
        # Set proper permissions for .htpasswd
        chmod 644 "$htpasswd_file" 2>/dev/null || true
        chown webapps:webapps "$htpasswd_file" 2>/dev/null || true
        
        # Use absolute path for .htpasswd to avoid issues
        local htpasswd_abs_path=$(readlink -f "$htpasswd_file" 2>/dev/null || echo "$htpasswd_file")
        
        # Add password protection rules to .htaccess
        {
            echo ""
            echo "# BEGIN WP-Login Protect - WordPress Manager"
            echo "# Added on $(date '+%Y-%m-%d %H:%M:%S')"
            echo "# Password protection for wp-login.php"
            echo "<Files \"wp-login.php\">"
            echo "    AuthType Basic"
            echo "    AuthName \"WordPress Login Protection\""
            echo "    AuthUserFile \"$htpasswd_abs_path\""
            echo "    Require valid-user"
            echo "</Files>"
            echo ""
            echo "# END WP-Login Protect - WordPress Manager"
        } >> "$htaccess_file"
        
        if [ $? -eq 0 ]; then
            print_success "Password protection enabled for $domain (username: $username)"
            ((count++))
        else
            print_error "Failed to enable password protection for $domain"
            ((failed++))
        fi
        
    done
    
    echo ""
    print_info "Summary: $count sites updated, $failed failed"
    print_warning "Remember: You need to enter username '$username' and password when accessing wp-login.php"
    
    if [ $failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Disable WP-Login password protection
wp-login-protect_disable() {
    print_info "Disabling password protection for wp-login.php on all WordPress sites..."
    
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
        local htpasswd_file="$docroot/.htpasswd"
        
        if [ ! -f "$htaccess_file" ]; then
            continue
        fi
        
        # Check if rule exists (both old and new names for compatibility)
        if ! grep -q "# BEGIN WP-Login Protect - WordPress Manager" "$htaccess_file" 2>/dev/null && \
           ! grep -q "# BEGIN WP-Login Block - WordPress Manager" "$htaccess_file" 2>/dev/null; then
            continue
        fi
        
        # Remove password protection rules using sed (both old and new names)
        sed -i '/^# BEGIN WP-Login Protect - WordPress Manager/,/^# END WP-Login Protect - WordPress Manager$/d' "$htaccess_file" 2>/dev/null
        sed -i '/^# BEGIN WP-Login Block - WordPress Manager/,/^# END WP-Login Block - WordPress Manager$/d' "$htaccess_file" 2>/dev/null
        # Remove multiple consecutive blank lines
        sed -i '/^$/N;/^\n$/d' "$htaccess_file" 2>/dev/null
        
        # Optionally remove .htpasswd file (comment out if you want to keep it)
        # if [ -f "$htpasswd_file" ]; then
        #     rm -f "$htpasswd_file"
        # fi
        
        if [ $? -eq 0 ]; then
            print_success "Password protection disabled for $domain"
            ((count++))
        else
            print_error "Failed to disable password protection for $domain"
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

# Check status of WP-Login password protection
wp-login-protect_status() {
    print_info "Checking WP-Login password protection status for all WordPress sites..."
    echo ""
    
    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        return 1
    fi
    
    local total=0
    local protected=0
    local unprotected=0
    
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
        echo -e "  ${GREEN}Protected: 0${NC}"
        echo -e "  ${RED}Not protected: 0${NC}"
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
        local htpasswd_file="$docroot/.htpasswd"
        ((total++))
        
        # Check both old and new rule names for compatibility
        if [ -f "$htaccess_file" ] && (grep -q "# BEGIN WP-Login Protect - WordPress Manager" "$htaccess_file" 2>/dev/null || \
            grep -q "# BEGIN WP-Login Block - WordPress Manager" "$htaccess_file" 2>/dev/null); then
            if [ -f "$htpasswd_file" ]; then
                echo -e "  ${GREEN}✓${NC} $domain - Password Protected"
                ((protected++))
            else
                echo -e "  ${YELLOW}⚠${NC} $domain - Rule exists but .htpasswd missing"
                ((unprotected++))
            fi
        else
            echo -e "  ${RED}✗${NC} $domain - Not protected"
            ((unprotected++))
        fi
        
    done
    
    echo ""
    echo "Summary:"
    echo "  Total WordPress sites: $total"
    echo -e "  ${GREEN}Password Protected: $protected${NC}"
    echo -e "  ${RED}Not protected: $unprotected${NC}"
}

###############################################################################
# Note: This module uses utility functions from main script
# Functions like print_info, print_success, get_wordpress_sites are available
# from the main script when this module is loaded via 'source'
###############################################################################

