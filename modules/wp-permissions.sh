#!/bin/bash

###############################################################################
# WP-Permissions Module
# Set proper file and directory permissions for WordPress sites
###############################################################################

# Module name
MODULE_NAME="wp-permissions"

###############################################################################
# Module Functions
###############################################################################

wp-permissions_description() {
    echo "Set WordPress File & Directory Permissions"
}

# This module doesn't have enabled/disabled status (it's per-site)
wp-permissions_has_status() {
    return 1  # false - no status
}

# Get owner and group for WordPress files
get_wp_owner() {
    local docroot="$1"

    # Prefer docroot owner/group to avoid inheriting wrong wp-config.php owner (can cause Forbidden)
    # Fallback to walking up directories if docroot is owned by root.
    if [ -d "$docroot" ]; then
        # DirectAdmin: infer owner from path /home/USERNAME/domains/.../public_html (avoids trusting wrong webapps owner)
        if [[ "$docroot" =~ ^/home/([^/]+)/domains/[^/]+/public_html ]]; then
            local da_user="${BASH_REMATCH[1]}"
            if [ -n "$da_user" ] && id "$da_user" &>/dev/null; then
                echo "${da_user}:${da_user}"
                return 0
            fi
        fi

        local owner_group=""
        owner_group=$(stat -c '%U:%G' "$docroot" 2>/dev/null || stat -f '%Su:%Sg' "$docroot" 2>/dev/null)

        local owner="${owner_group%%:*}"
        local group="${owner_group#*:}"

        # If docroot is owned by webapps (wrong state), try path to get real DA user
        if [ "$owner" = "webapps" ] && [[ "$docroot" =~ /home/([^/]+)/ ]]; then
            local da_user="${BASH_REMATCH[1]}"
            if [ -n "$da_user" ] && [ "$da_user" != "webapps" ] && id "$da_user" &>/dev/null; then
                echo "${da_user}:${da_user}"
                return 0
            fi
        fi

        # If docroot is root-owned, try parent dirs to find a non-root owner
        if [ "$owner" = "root" ]; then
            local parent="$docroot"
            local i=0
            while [ $i -lt 5 ]; do
                parent="$(dirname "$parent")"
                if [ -z "$parent" ] || [ "$parent" = "/" ]; then
                    break
                fi
                owner_group=$(stat -c '%U:%G' "$parent" 2>/dev/null || stat -f '%Su:%Sg' "$parent" 2>/dev/null)
                owner="${owner_group%%:*}"
                group="${owner_group#*:}"
                if [ -n "$owner" ] && [ "$owner" != "root" ] && [ "$owner" != "webapps" ]; then
                    echo "$owner:$group"
                    return 0
                fi
                i=$((i + 1))
            done
        fi

        echo "$owner:$group"
        return 0
    fi

    echo "root:root"
}

# Set permissions for WordPress site
set_wp_permissions() {
    local docroot="$1"
    local domain="$2"

    if [ ! -d "$docroot" ]; then
        return 1
    fi

    # Get owner and group
    local owner_group=$(get_wp_owner "$docroot")
    local owner=$(echo "$owner_group" | cut -d: -f1)
    local group=$(echo "$owner_group" | cut -d: -f2)

    local errors=0
    local step_failed=0

    echo -n "  - Setting directory permissions (755)... "
    step_failed=0
    find "$docroot" -type d -print0 | xargs -0 chmod 755 2>/dev/null || step_failed=1
    if [ $step_failed -eq 0 ]; then
        echo "Done"
    else
        echo "Failed"
        ((errors++))
    fi

    echo -n "  - Setting file permissions (644)... "
    step_failed=0
    find "$docroot" -type f -print0 | xargs -0 chmod 644 2>/dev/null || step_failed=1
    if [ $step_failed -eq 0 ]; then
        echo "Done"
    else
        echo "Failed"
        ((errors++))
    fi

    # Set wp-config.php to 600 (more secure)
    if [ -f "$docroot/wp-config.php" ]; then
        echo -n "  - Setting wp-config.php permissions (600)... "
        step_failed=0
        chmod 600 "$docroot/wp-config.php" 2>/dev/null || step_failed=1
        if [ $step_failed -eq 0 ]; then
            echo "Done"
        else
            # Fallback to 640 to reduce risk of Forbidden on setups where PHP/Apache needs group-read.
            chmod 640 "$docroot/wp-config.php" 2>/dev/null || true
            echo "Failed"
            ((errors++))
        fi
    fi

    # Set .htaccess to 644
    if [ -f "$docroot/.htaccess" ]; then
        echo -n "  - Setting .htaccess permissions (644)... "
        step_failed=0
        chmod 644 "$docroot/.htaccess" 2>/dev/null || step_failed=1
        if [ $step_failed -eq 0 ]; then
            echo "Done"
        else
            echo "Failed"
            ((errors++))
        fi
    fi

    # Set wp-content/uploads to 755 (and ensure directories are writable)
    if [ -d "$docroot/wp-content/uploads" ]; then
        echo -n "  - Setting wp-content/uploads permissions... "
        step_failed=0
        find "$docroot/wp-content/uploads" -type d -print0 | xargs -0 chmod 755 2>/dev/null || step_failed=1
        find "$docroot/wp-content/uploads" -type f -print0 | xargs -0 chmod 644 2>/dev/null || step_failed=1
        if [ $step_failed -eq 0 ]; then
            echo "Done"
        else
            echo "Failed"
            ((errors++))
        fi
    fi

    # Ensure wp-content/upgrade exists and is readable/writable for updates
    echo -n "  - Setting wp-content/upgrade permissions... "
    step_failed=0
    if [ -d "$docroot/wp-content" ]; then
        mkdir -p "$docroot/wp-content/upgrade" 2>/dev/null || step_failed=1
        if [ -d "$docroot/wp-content/upgrade" ]; then
            chmod 755 "$docroot/wp-content/upgrade" 2>/dev/null || step_failed=1
            find "$docroot/wp-content/upgrade" -type d -print0 | xargs -0 chmod 755 2>/dev/null || true
            find "$docroot/wp-content/upgrade" -type f -print0 | xargs -0 chmod 644 2>/dev/null || true
        else
            step_failed=1
        fi
    else
        step_failed=1
    fi
    if [ $step_failed -eq 0 ]; then
        echo "Done"
    else
        echo "Failed"
        ((errors++))
    fi

    # Set ownership recursively
    echo -n "  - Setting ownership ($owner:$group)... "
    step_failed=0
    # Safety: do not chown to root or webapps (causes Forbidden on DirectAdmin)
    if [ -z "$owner" ] || [ -z "$group" ] || [ "$owner" = "root" ] || [ "$group" = "root" ] || [ "$owner" = "webapps" ] || [ "$group" = "webapps" ]; then
        step_failed=1
    else
        chown -R "$owner:$group" "$docroot" 2>/dev/null || step_failed=1
    fi
    if [ $step_failed -eq 0 ]; then
        echo "Done"
    else
        echo "Failed"
        ((errors++))
    fi

    # Special handling for wp-content/uploads - ensure web server can write
    if [ -d "$docroot/wp-content/uploads" ]; then
        echo -n "  - Setting wp-content/uploads group permissions... "
        # Try to add group write permission for uploads directory
        chmod 775 "$docroot/wp-content/uploads" 2>/dev/null || true
        # Set group ownership if possible
        if [ -n "$group" ] && [ "$group" != "root" ]; then
            chgrp -R "$group" "$docroot/wp-content/uploads" 2>/dev/null || true
        fi
        echo "Done"
    fi

    if [ $errors -gt 0 ]; then
        return 1
    fi

    return 0
}

# Check permissions for WordPress site
check_wp_permissions() {
    local docroot="$1"
    local domain="$2"

    if [ ! -d "$docroot" ]; then
        return 2  # Directory not found
    fi

    local issues=0
    local warnings=0

    # Check wp-config.php permissions (should be 600)
    if [ -f "$docroot/wp-config.php" ]; then
        local wp_config_perm=$(stat -c '%a' "$docroot/wp-config.php" 2>/dev/null || stat -f '%A' "$docroot/wp-config.php" 2>/dev/null)
        if [ "$wp_config_perm" != "600" ] && [ "$wp_config_perm" != "400" ] && [ "$wp_config_perm" != "640" ]; then
            ((issues++))
        fi
    fi

    # Check if directories have proper permissions (should be 755 or 775)
    local dirs_with_bad_perm=$(find "$docroot" -type d ! -perm 755 ! -perm 775 2>/dev/null | head -5 | wc -l)
    if [ "$dirs_with_bad_perm" -gt 0 ]; then
        ((warnings++))
    fi

    # Check if files have proper permissions (should be 644 or 640)
    local files_with_bad_perm=$(find "$docroot" -type f ! -perm 644 ! -perm 640 ! -perm 600 ! -perm 400 2>/dev/null | head -5 | wc -l)
    if [ "$files_with_bad_perm" -gt 0 ]; then
        ((warnings++))
    fi

    # Check wp-content/uploads permissions
    if [ -d "$docroot/wp-content/uploads" ]; then
        local uploads_perm=$(stat -c '%a' "$docroot/wp-content/uploads" 2>/dev/null || stat -f '%A' "$docroot/wp-content/uploads" 2>/dev/null)
        if [ "$uploads_perm" != "755" ] && [ "$uploads_perm" != "775" ]; then
            ((warnings++))
        fi
    fi

    if [ $issues -gt 0 ]; then
        return 1  # Has security issues
    elif [ $warnings -gt 0 ]; then
        return 3  # Has warnings but not critical
    else
        return 0  # All good
    fi
}

# Extract domain from URL (handles http://, https://, trailing slash)
# Usage: extract_domain url
extract_domain() {
    local url="$1"

    # Remove leading/trailing whitespace
    url=$(echo "$url" | xargs)

    # Remove http:// or https://
    url="${url#http://}"
    url="${url#https://}"

    # Remove www. prefix if exists
    url="${url#www.}"

    # Remove trailing slash
    url="${url%/}"

    # Extract domain (remove path if exists)
    url="${url%%/*}"

    # Remove port if exists (e.g., domain.com:8080)
    url="${url%%:*}"

    echo "$url"
}

# Select a specific website by entering domain
# Usage: select_website result_var
# Sets result_var to selected site (format: domain:docroot) or empty if cancelled
select_website() {
    local result_var="$1"

    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        eval "$result_var=''"
        return 1
    fi

    # Get all WordPress sites into array
    local sites_output
    sites_output=$(get_wordpress_sites 2>&1)
    local sites=()
    local valid_sites=()

    if [ -n "$sites_output" ]; then
        while IFS= read -r site; do
            if [ -n "$site" ]; then
                sites+=("$site")
                IFS=: read -r domain docroot <<< "$site"
                if [ -n "$domain" ] && [ -n "$docroot" ]; then
                    valid_sites+=("$site")
                fi
            fi
        done <<< "$sites_output"
    fi

    if [ ${#valid_sites[@]} -eq 0 ]; then
        print_warning "No WordPress sites found"
        eval "$result_var=''"
        return 1
    fi

    echo ""
    echo -n "Cần set domain nào? "
    read input_url

    if [ -z "$input_url" ] || [ "$input_url" == "0" ]; then
        eval "$result_var=''"
        return 1
    fi

    # Extract domain from URL
    local input_domain=$(extract_domain "$input_url")

    if [ -z "$input_domain" ]; then
        print_error "Không thể xác định domain từ input: '$input_url'"
        eval "$result_var=''"
        return 1
    fi

    # Search for the domain in valid sites
    local found_site=""
    for site in "${valid_sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"
        # Compare extracted domain with site domain
        if [ "$domain" == "$input_domain" ]; then
            found_site="$site"
            break
        fi
    done

    if [ -n "$found_site" ]; then
        eval "$result_var=\"$found_site\""
        return 0
    else
        print_error "Domain '$input_domain' không tìm thấy trong danh sách WordPress sites"
        echo ""
        print_info "Các domain có sẵn:"
        for site in "${valid_sites[@]}"; do
            IFS=: read -r domain docroot <<< "$site"
            echo "  - $domain"
        done
        eval "$result_var=''"
        return 1
    fi
}

# Enable permissions setting
wp-permissions_enable() {
    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        return 1
    fi

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

    # Ask user to select scope
    echo ""
    echo "Select scope:"
    echo "  1) All WordPress sites (${#sites[@]} sites)"
    echo "  2) Specific website"
    echo "  0) Cancel"
    echo ""
    echo -n "Select option: "
    read scope_choice

    local selected_sites=()

    case "$scope_choice" in
        1)
            # All sites
            selected_sites=("${sites[@]}")
            print_info "Setting proper file and directory permissions for all WordPress sites..."
            ;;
        2)
            # Specific site
            local selected=""
            select_website selected
            if [ -z "$selected" ]; then
                print_info "Operation cancelled"
                return 0
            fi
            selected_sites=("$selected")
            IFS=: read -r domain docroot <<< "$selected"
            if [ -n "$domain" ]; then
                print_info "Setting proper file and directory permissions for $domain..."
            else
                print_error "Invalid site selection"
                return 1
            fi
            ;;
        0)
            print_info "Operation cancelled"
            return 0
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac

    if [ ${#selected_sites[@]} -eq 0 ]; then
        print_warning "No sites selected"
        return 0
    fi

    local count=0
    local failed=0

    echo ""
    print_info "Found ${#selected_sites[@]} WordPress site(s) to process"
    echo ""
    print_info "Setting permissions:"
    print_info "  - Directories: 755"
    print_info "  - Files: 644"
    print_info "  - wp-config.php: 600"
    print_info "  - .htaccess: 644"
    print_info "  - wp-content/uploads: 755 (directories), 644 (files)"
    echo ""

    # Process each site
    for site in "${selected_sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"

        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi

        if [ ! -d "$docroot" ]; then
            print_warning "Directory not found for $domain: $docroot"
            ((failed++))
            continue
        fi

        # Get owner info
        local owner_group=$(get_wp_owner "$docroot")
        local owner=$(echo "$owner_group" | cut -d: -f1)
        local group=$(echo "$owner_group" | cut -d: -f2)

        print_info "Processing $domain (owner: $owner:$group)..."

        if set_wp_permissions "$docroot" "$domain"; then
            print_success "Permissions set for $domain"
            ((count++))
        else
            print_error "Failed to set permissions for $domain"
            ((failed++))
        fi

    done

    echo ""
    print_info "Summary: $count sites updated, $failed failed"
    print_info "Permissions have been set according to WordPress best practices"

    if [ $failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Disable permissions (show info only, as permissions can't really be "disabled")
wp-permissions_disable() {
    print_info "Note: File permissions cannot be 'disabled'"
    print_info "This option will show current permission status"
    echo ""

    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        return 1
    fi

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

    # Ask user to select scope
    echo ""
    echo "Select scope:"
    echo "  1) All WordPress sites (${#sites[@]} sites)"
    echo "  2) Specific website"
    echo "  0) Cancel"
    echo ""
    echo -n "Select option: "
    read scope_choice

    local selected_sites=()

    case "$scope_choice" in
        1)
            # All sites
            selected_sites=("${sites[@]}")
            print_info "Current permission status for all WordPress sites:"
            ;;
        2)
            # Specific site
            local selected=""
            select_website selected
            if [ -z "$selected" ]; then
                print_info "Operation cancelled"
                return 0
            fi
            selected_sites=("$selected")
            IFS=: read -r domain docroot <<< "$selected"
            print_info "Current permission status for $domain:"
            ;;
        0)
            print_info "Operation cancelled"
            return 0
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac

    if [ ${#selected_sites[@]} -eq 0 ]; then
        print_warning "No sites selected"
        return 0
    fi

    echo ""

    # Process each site
    for site in "${selected_sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"

        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi

        if [ ! -d "$docroot" ]; then
            print_warning "Directory not found for $domain: $docroot"
            continue
        fi

        # Get owner info
        local owner_group=$(get_wp_owner "$docroot")
        local owner=$(echo "$owner_group" | cut -d: -f1)
        local group=$(echo "$owner_group" | cut -d: -f2)

        # Check permissions
        check_wp_permissions "$docroot" "$domain"
        local status=$?

        if [ $status -eq 0 ]; then
            echo -e "  ${GREEN}✓${NC} $domain - Permissions OK (owner: $owner:$group)"
        elif [ $status -eq 1 ]; then
            echo -e "  ${RED}✗${NC} $domain - Security issues found (owner: $owner:$group)"
        elif [ $status -eq 3 ]; then
            echo -e "  ${YELLOW}⚠${NC} $domain - Some permission warnings (owner: $owner:$group)"
        else
            echo -e "  ${RED}✗${NC} $domain - Directory not found"
        fi

    done

    echo ""
    print_info "To fix permissions, use 'Enable' option"

    return 0
}

# Check status of permissions
wp-permissions_status() {
    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        return 1
    fi

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
        echo -e "  ${GREEN}OK: 0${NC}"
        echo -e "  ${YELLOW}Warnings: 0${NC}"
        echo -e "  ${RED}Issues: 0${NC}"
        return 0
    fi

    # Ask user to select scope
    echo ""
    echo "Select scope:"
    echo "  1) All WordPress sites (${#sites[@]} sites)"
    echo "  2) Specific website"
    echo "  0) Cancel"
    echo ""
    echo -n "Select option: "
    read scope_choice

    local selected_sites=()

    case "$scope_choice" in
        1)
            # All sites
            selected_sites=("${sites[@]}")
            print_info "Checking file and directory permissions for all WordPress sites..."
            ;;
        2)
            # Specific site
            local selected=""
            select_website selected
            if [ -z "$selected" ]; then
                print_info "Operation cancelled"
                return 0
            fi
            selected_sites=("$selected")
            IFS=: read -r domain docroot <<< "$selected"
            print_info "Checking file and directory permissions for $domain..."
            ;;
        0)
            print_info "Operation cancelled"
            return 0
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac

    if [ ${#selected_sites[@]} -eq 0 ]; then
        print_warning "No sites selected"
        return 0
    fi

    echo ""

    local total=0
    local ok=0
    local issues=0
    local warnings=0

    # Process each site
    for site in "${selected_sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"

        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi

        ((total++))

        if [ ! -d "$docroot" ]; then
            echo -e "  ${RED}✗${NC} $domain - Directory not found"
            ((issues++))
            continue
        fi

        # Get owner info
        local owner_group=$(get_wp_owner "$docroot")
        local owner=$(echo "$owner_group" | cut -d: -f1)
        local group=$(echo "$owner_group" | cut -d: -f2)

        # Check permissions
        check_wp_permissions "$docroot" "$domain"
        local status=$?

        if [ $status -eq 0 ]; then
            echo -e "  ${GREEN}✓${NC} $domain - Permissions OK"
            ((ok++))
        elif [ $status -eq 1 ]; then
            echo -e "  ${RED}✗${NC} $domain - Security issues (wp-config.php permissions)"
            ((issues++))
        elif [ $status -eq 3 ]; then
            echo -e "  ${YELLOW}⚠${NC} $domain - Permission warnings"
            ((warnings++))
        else
            echo -e "  ${RED}✗${NC} $domain - Check failed"
            ((issues++))
        fi

    done

    echo ""
    echo "Summary:"
    echo "  Total WordPress sites: $total"
    echo -e "  ${GREEN}OK: $ok${NC}"
    echo -e "  ${YELLOW}Warnings: $warnings${NC}"
    echo -e "  ${RED}Issues: $issues${NC}"
    echo ""

    if [ $issues -gt 0 ] || [ $warnings -gt 0 ]; then
        print_info "Recommended permissions:"
        print_info "  - Directories: 755"
        print_info "  - Files: 644"
        print_info "  - wp-config.php: 600"
        print_info "  - .htaccess: 644"
        print_info "  - wp-content/uploads: 755 (directories), 644 (files)"
        print_info ""
        print_info "Use 'Enable' option to fix permissions"
    fi
}

###############################################################################
# Note: This module uses utility functions from main script
# Functions like print_info, print_success, get_wordpress_sites are available
# from the main script when this module is loaded via 'source'
###############################################################################

