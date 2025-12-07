#!/bin/bash

###############################################################################
# WP-Cron Disable Module
# Disable WordPress cron by adding define('DISABLE_WP_CRON', true); to wp-config.php
###############################################################################

# Module name
MODULE_NAME="wp-cron-disable"

###############################################################################
# Module Functions
###############################################################################

wp-cron-disable_description() {
    echo "Disable WP-Cron"
}

# Enable WP-Cron disabling
wp-cron-disable_enable() {
    print_info "Enabling WP-Cron disable for all WordPress sites..."
    
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
        
        local wp_config="$docroot/wp-config.php"
        
        # Check if wp-config.php exists
        if [ ! -f "$wp_config" ]; then
            print_warning "wp-config.php not found for $domain"
            continue
        fi
        
        # Check if WP-Cron disable block already exists (added by WordPress Manager)
        if grep -q "BEGIN WP-Cron Disable - WordPress Manager" "$wp_config" 2>/dev/null; then
            print_warning "WP-Cron disable block already exists for $domain"
            continue
        fi
        
        # Check if user has already added DISABLE_WP_CRON manually
        local has_existing_define=false
        local existing_define_line=0
        if grep -q "define.*DISABLE_WP_CRON" "$wp_config" 2>/dev/null; then
            has_existing_define=true
            existing_define_line=$(grep -n "define.*DISABLE_WP_CRON" "$wp_config" | head -1 | cut -d: -f1)
            print_info "Found existing DISABLE_WP_CRON definition for $domain, will replace with managed block"
        fi
        
        # Create backup
        local backup_file="${wp_config}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$wp_config" "$backup_file" 2>/dev/null
        
        local temp_file=$(mktemp)
        
        if [ "$has_existing_define" = true ]; then
            # Replace existing define with managed block
            local total_lines=$(wc -l < "$wp_config" | tr -d ' ')
            
            # Remove the existing define line and any comment before it (if it's a single-line comment)
            {
                head -n $((existing_define_line - 1)) "$wp_config"
                echo ""
                echo "/* BEGIN WP-Cron Disable - WordPress Manager - Added on $(date '+%Y-%m-%d %H:%M:%S') */"
                echo "define('DISABLE_WP_CRON', true);"
                echo "/* END WP-Cron Disable - WordPress Manager */"
                tail -n +$((existing_define_line + 1)) "$wp_config"
            } > "$temp_file"
        else
            # Find the insertion point (before "/* That's all, stop editing! */" or at end of file)
            local insert_line
            local total_lines=$(wc -l < "$wp_config" | tr -d ' ')
            
            if grep -q "That's all, stop editing" "$wp_config" 2>/dev/null; then
                # Insert before the "That's all" comment
                insert_line=$(grep -n "That's all, stop editing" "$wp_config" | head -1 | cut -d: -f1)
            else
                # Insert at the end of file
                insert_line=$((total_lines + 1))
            fi
            
            # Insert the define statement with BEGIN/END comments
            if [ $insert_line -gt $total_lines ]; then
                # Insert at the end
                {
                    cat "$wp_config"
                    echo ""
                    echo "/* BEGIN WP-Cron Disable - WordPress Manager - Added on $(date '+%Y-%m-%d %H:%M:%S') */"
                    echo "define('DISABLE_WP_CRON', true);"
                    echo "/* END WP-Cron Disable - WordPress Manager */"
                } > "$temp_file"
            else
                # Insert before the "That's all" comment or at specific line
                {
                    head -n $((insert_line - 1)) "$wp_config"
                    echo ""
                    echo "/* BEGIN WP-Cron Disable - WordPress Manager - Added on $(date '+%Y-%m-%d %H:%M:%S') */"
                    echo "define('DISABLE_WP_CRON', true);"
                    echo "/* END WP-Cron Disable - WordPress Manager */"
                    tail -n +$insert_line "$wp_config"
                } > "$temp_file"
            fi
        fi
        
        # Replace original file
        if mv "$temp_file" "$wp_config" 2>/dev/null; then
            # Restore ownership if possible
            chown webapps:webapps "$wp_config" 2>/dev/null || true
            chmod 644 "$wp_config" 2>/dev/null || true
            
            print_success "Disabled WP-Cron for $domain"
            ((count++))
        else
            print_error "Failed to disable WP-Cron for $domain"
            # Restore from backup if exists
            if [ -f "$backup_file" ]; then
                mv "$backup_file" "$wp_config" 2>/dev/null
            fi
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

# Disable WP-Cron disabling (remove the define)
wp-cron-disable_disable() {
    print_info "Re-enabling WP-Cron for all WordPress sites..."
    
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
        
        local wp_config="$docroot/wp-config.php"
        
        if [ ! -f "$wp_config" ]; then
            continue
        fi
        
        # Check if WP-Cron disable block exists
        if ! grep -q "BEGIN WP-Cron Disable - WordPress Manager" "$wp_config" 2>/dev/null; then
            continue
        fi
        
        # Create backup
        local backup_file="${wp_config}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$wp_config" "$backup_file" 2>/dev/null
        
        # Remove the block from BEGIN to END
        local temp_file=$(mktemp)
        
        # Remove from "BEGIN WP-Cron Disable" to "END WP-Cron Disable" including blank lines
        # Also remove blank line before BEGIN if it exists
        sed -e '/\/\* BEGIN WP-Cron Disable - WordPress Manager/,/\/\* END WP-Cron Disable - WordPress Manager \*\//d' \
            "$wp_config" > "$temp_file" 2>/dev/null
        
        # Remove multiple consecutive blank lines
        sed -i '/^$/N;/^\n$/d' "$temp_file" 2>/dev/null || \
        sed '/^$/N;/^\n$/d' "$temp_file" > "${temp_file}.tmp" 2>/dev/null && mv "${temp_file}.tmp" "$temp_file" 2>/dev/null || true
        
        # Replace original file
        if mv "$temp_file" "$wp_config" 2>/dev/null; then
            # Restore ownership if possible
            chown webapps:webapps "$wp_config" 2>/dev/null || true
            chmod 644 "$wp_config" 2>/dev/null || true
            
            print_success "Re-enabled WP-Cron for $domain"
            ((count++))
        else
            print_error "Failed to re-enable WP-Cron for $domain"
            # Restore from backup if exists
            if [ -f "$backup_file" ]; then
                mv "$backup_file" "$wp_config" 2>/dev/null
            fi
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

# Check status of WP-Cron disabling
wp-cron-disable_status() {
    print_info "Checking WP-Cron disable status for all WordPress sites..."
    echo ""
    
    # Check if get_wordpress_sites function exists
    if ! type get_wordpress_sites &>/dev/null; then
        print_error "get_wordpress_sites function not available"
        return 1
    fi
    
    local total=0
    local disabled=0
    local enabled=0
    
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
        echo -e "  ${GREEN}WP-Cron Disabled: 0${NC}"
        echo -e "  ${RED}WP-Cron Enabled: 0${NC}"
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
        
        local wp_config="$docroot/wp-config.php"
        ((total++))
        
        if [ -f "$wp_config" ] && grep -q "BEGIN WP-Cron Disable - WordPress Manager" "$wp_config" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $domain - WP-Cron Disabled"
            ((disabled++))
        else
            echo -e "  ${RED}✗${NC} $domain - WP-Cron Enabled"
            ((enabled++))
        fi
        
    done
    
    echo ""
    echo "Summary:"
    echo "  Total WordPress sites: $total"
    echo -e "  ${GREEN}WP-Cron Disabled: $disabled${NC}"
    echo -e "  ${RED}WP-Cron Enabled: $enabled${NC}"
}

###############################################################################
# Note: This module uses utility functions from main script
# Functions like print_info, print_success, get_wordpress_sites are available
# from the main script when this module is loaded via 'source'
###############################################################################

