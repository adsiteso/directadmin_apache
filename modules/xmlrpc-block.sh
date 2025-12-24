#!/bin/bash

###############################################################################
# XML-RPC Block Module
# Block/unblock xmlrpc.php access for WordPress sites
###############################################################################

# Module name
MODULE_NAME="xmlrpc-block"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DA_USERDATA="/usr/local/directadmin/data/users"

###############################################################################
# Module Functions
###############################################################################

xmlrpc-block_description() {
    echo "Block XML-RPC Access (xmlrpc.php)"
}

# Enable XML-RPC blocking
xmlrpc-block_enable() {
    print_info "Enabling XML-RPC blocking for all WordPress sites..."

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
        if grep -q "# BEGIN XML-RPC Block - WordPress Manager" "$htaccess_file" 2>/dev/null; then
            print_warning "XML-RPC block already exists for $domain"
            continue
        fi

        # Add blocking rules
        {
            echo ""
            echo "# BEGIN XML-RPC Block - WordPress Manager"
            echo "# Added on $(date '+%Y-%m-%d %H:%M:%S')"
            echo "<Files xmlrpc.php>"
            echo "    Order allow,deny"
            echo "    Deny from all"
            echo "</Files>"
            echo ""
            echo "# END XML-RPC Block - WordPress Manager"
        } >> "$htaccess_file"

        if [ $? -eq 0 ]; then
            print_success "Blocked XML-RPC for $domain"
            ((count++))
        else
            print_error "Failed to block XML-RPC for $domain"
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

# Disable XML-RPC blocking
xmlrpc-block_disable() {
    print_info "Disabling XML-RPC blocking for all WordPress sites..."

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

    local skipped_no_htaccess=0
    local skipped_no_rule=0
    local skipped_invalid=0

    # Process each site
    for site in "${sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"

        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            ((skipped_invalid++))
            continue
        fi

        local htaccess_file="$docroot/.htaccess"

        if [ ! -f "$htaccess_file" ]; then
            ((skipped_no_htaccess++))
            continue
        fi

        # Check if rule exists
        if ! grep -q "# BEGIN XML-RPC Block - WordPress Manager" "$htaccess_file" 2>/dev/null; then
            ((skipped_no_rule++))
            continue
        fi

        # Remove blocking rules using sed
        # Remove from "# BEGIN XML-RPC Block" to "# END XML-RPC Block" including blank lines
        sed -i '/^# BEGIN XML-RPC Block - WordPress Manager/,/^# END XML-RPC Block - WordPress Manager$/d' "$htaccess_file" 2>/dev/null
        # Remove multiple consecutive blank lines
        sed -i '/^$/N;/^\n$/d' "$htaccess_file" 2>/dev/null

        if [ $? -eq 0 ]; then
            print_success "Unblocked XML-RPC for $domain"
            ((count++))
        else
            print_error "Failed to unblock XML-RPC for $domain"
            ((failed++))
        fi

    done

    # Show skipped reasons if any
    if [ $skipped_no_htaccess -gt 0 ] || [ $skipped_no_rule -gt 0 ] || [ $skipped_invalid -gt 0 ]; then
        echo ""
        if [ $skipped_no_rule -gt 0 ]; then
            print_info "Skipped $skipped_no_rule site(s) - XML-RPC block rule not found (may not be enabled)"
        fi
        if [ $skipped_no_htaccess -gt 0 ]; then
            print_info "Skipped $skipped_no_htaccess site(s) - .htaccess file not found"
        fi
        if [ $skipped_invalid -gt 0 ]; then
            print_info "Skipped $skipped_invalid site(s) - invalid domain/docroot"
        fi
    fi

    echo ""
    print_info "Summary: $count sites updated, $failed failed"

    if [ $failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Check status of XML-RPC blocking
xmlrpc-block_status() {
    print_info "Checking XML-RPC block status for all WordPress sites..."
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

        if [ -f "$htaccess_file" ] && grep -q "# BEGIN XML-RPC Block - WordPress Manager" "$htaccess_file" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $domain - Blocked"
            ((blocked++))
        else
            echo -e "  ${RED}✗${NC} $domain - Not blocked"
            ((unblocked++))
        fi

    done

    echo ""
    echo "Summary:"
    echo "  Total WordPress sites: $total"
    echo -e "  ${GREEN}Blocked: $blocked${NC}"
    echo -e "  ${RED}Not blocked: $unblocked${NC}"
}

###############################################################################
# Note: This module uses utility functions from main script
# Functions like print_info, print_success, get_wordpress_sites are available
# from the main script when this module is loaded via 'source'
###############################################################################

