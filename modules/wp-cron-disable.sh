#!/bin/bash

###############################################################################
# WP-Cron Disable Module
# Disable WordPress automatic cron and setup system cron to run wp-cron.php every 15 minutes
###############################################################################

# Module name
MODULE_NAME="wp-cron-disable"

# Get config directory (use from main script if available, otherwise calculate)
if [ -z "$CONFIG_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    CONFIG_DIR="${SCRIPT_DIR}/config"
fi
CRON_JOBS_FILE="${CONFIG_DIR}/wp-cron-jobs.txt"

###############################################################################
# Module Functions
###############################################################################

wp-cron-disable_description() {
    echo "Disable WP-Cron (Use System Cron)"
}

# Create wrapper script that runs wp-cron for all sites
setup_wp_cron_wrapper() {
    local wrapper_script="${CONFIG_DIR}/wp-cron-wrapper.sh"

    # Create wrapper script
    mkdir -p "$(dirname "$wrapper_script")" 2>/dev/null || true
    cat > "$wrapper_script" << 'WRAPPER_EOF'
#!/bin/bash
# WP-Cron Wrapper Script - WordPress Manager
# Runs wp-cron.php for all WordPress sites configured with DISABLE_WP_CRON
# This script is managed by WordPress Manager - wp-cron-disable module

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
CRON_JOBS_FILE="${CONFIG_DIR}/wp-cron-jobs.txt"

# Check if tracking file exists
if [ ! -f "$CRON_JOBS_FILE" ]; then
    exit 0
fi

# Read sites from tracking file and run wp-cron
# Limit concurrent processes to avoid overwhelming the server
# All sites will be processed, but only MAX_CONCURRENT will run at the same time
MAX_CONCURRENT=20
PIDS=()
TOTAL_SITES=0
PROCESSED_SITES=0

# First, count total sites to process
while IFS=: read -r domain docroot || [ -n "$domain" ]; do
    if [ -z "$domain" ] || [ -z "$docroot" ]; then
        continue
    fi
    if [ -f "$docroot/wp-config.php" ] && grep -q "BEGIN WP-Cron Disable - WordPress Manager" "$docroot/wp-config.php" 2>/dev/null; then
        ((TOTAL_SITES++))
    fi
done < "$CRON_JOBS_FILE"

# Helper function to clean up finished PIDs
cleanup_finished_pids() {
    local NEW_PIDS=()
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            NEW_PIDS+=("$pid")
        else
            ((PROCESSED_SITES++))
        fi
    done
    PIDS=("${NEW_PIDS[@]}")
}

# Process all sites
while IFS=: read -r domain docroot || [ -n "$domain" ]; do
    if [ -z "$domain" ] || [ -z "$docroot" ]; then
        continue
    fi

    # Check if wp-config.php has DISABLE_WP_CRON define
    if [ -f "$docroot/wp-config.php" ] && grep -q "BEGIN WP-Cron Disable - WordPress Manager" "$docroot/wp-config.php" 2>/dev/null; then
        # Wait if we've reached max concurrent jobs
        # This loop ensures we wait for a slot to become available
        while [ ${#PIDS[@]} -ge $MAX_CONCURRENT ]; do
            sleep 0.3
            cleanup_finished_pids
        done

        # Run wp-cron.php using wget or curl in background
        if command -v wget &> /dev/null; then
            /usr/bin/wget -q -O /dev/null "https://${domain}/wp-cron.php?doing_wp_cron" --timeout=10 --tries=1 >/dev/null 2>&1 &
            PIDS+=($!)
        elif command -v curl &> /dev/null; then
            /usr/bin/curl -s -o /dev/null --max-time 10 "https://${domain}/wp-cron.php?doing_wp_cron" >/dev/null 2>&1 &
            PIDS+=($!)
        fi
    fi
done < "$CRON_JOBS_FILE"

# Wait for all remaining background jobs to complete (with timeout)
TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ] && [ ${#PIDS[@]} -gt 0 ]; do
    sleep 1
    ((ELAPSED++))
    cleanup_finished_pids
done

# Final cleanup and wait for any remaining jobs
cleanup_finished_pids
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
    ((PROCESSED_SITES++))
done
WRAPPER_EOF
    chmod +x "$wrapper_script" 2>/dev/null || true

    # Check if wrapper cron job already exists
    if crontab -l 2>/dev/null | grep -q "wp-cron-wrapper.sh.*WordPress Manager"; then
        return 1  # Already exists
    fi

    # Add single cron job that calls wrapper script (runs every 15 minutes)
    # Use absolute path and proper escaping
    local wrapper_abs_path=$(readlink -f "$wrapper_script" 2>/dev/null || echo "$wrapper_script")
    local cron_cmd="*/15 * * * * /bin/bash ${wrapper_abs_path} >/dev/null 2>&1"
    local cron_comment="# WP-Cron Wrapper - WordPress Manager (runs all sites)"

    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_cmd $cron_comment") | crontab - 2>/dev/null

    return $?
}

# Remove wrapper cron job
remove_wp_cron_wrapper() {
    # Remove wrapper cron job from crontab
    crontab -l 2>/dev/null | grep -v "wp-cron-wrapper.sh.*WordPress Manager" | crontab - 2>/dev/null

    # Remove wrapper script
    local wrapper_script="${CONFIG_DIR}/wp-cron-wrapper.sh"
    rm -f "$wrapper_script" 2>/dev/null || true
}

# Helper function to add site to tracking file (no longer creates individual cron jobs)
add_wp_cron_job() {
    local domain="$1"
    local docroot="$2"

    # Check if already in tracking file
    if [ -f "$CRON_JOBS_FILE" ] && grep -q "^${domain}:" "$CRON_JOBS_FILE" 2>/dev/null; then
        return 1  # Already exists
    fi

    # Add to tracking file
    mkdir -p "$(dirname "$CRON_JOBS_FILE")" 2>/dev/null || true
    echo "${domain}:${docroot}" >> "$CRON_JOBS_FILE" 2>/dev/null || true

    # Setup wrapper script and cron job if not exists (with lock to prevent race condition)
    local lock_file="${CONFIG_DIR}/.wp-cron-wrapper.lock"
    if [ ! -f "$lock_file" ]; then
        touch "$lock_file" 2>/dev/null || true
        if ! crontab -l 2>/dev/null | grep -q "wp-cron-wrapper.sh.*WordPress Manager"; then
            setup_wp_cron_wrapper
        fi
        rm -f "$lock_file" 2>/dev/null || true
    else
        # Lock exists, wait a bit and check again
        sleep 0.5
        if ! crontab -l 2>/dev/null | grep -q "wp-cron-wrapper.sh.*WordPress Manager"; then
            setup_wp_cron_wrapper
        fi
    fi

    return 0
}

# Helper function to remove site from tracking file
remove_wp_cron_job() {
    local domain="$1"

    # Remove from tracking file
    if [ -f "$CRON_JOBS_FILE" ]; then
        local temp_file=$(mktemp)
        grep -v "^${domain}:" "$CRON_JOBS_FILE" > "$temp_file" 2>/dev/null
        mv "$temp_file" "$CRON_JOBS_FILE" 2>/dev/null || true

        # If tracking file is empty, remove wrapper cron job
        if [ ! -s "$CRON_JOBS_FILE" ]; then
            remove_wp_cron_wrapper
            rm -f "$CRON_JOBS_FILE" 2>/dev/null || true
        fi
    fi
}

# Cleanup orphan cron jobs (cron jobs without corresponding define in wp-config.php)
# This function checks ALL WP-Cron cron jobs in crontab and removes those without define
cleanup_orphan_cron_jobs() {
    local cleaned=0

    # Check if tracking file exists
    if [ ! -f "$CRON_JOBS_FILE" ]; then
        # If no tracking file, check for old individual cron jobs and remove wrapper if exists
        local has_old_jobs=$(crontab -l 2>/dev/null | grep "wp-cron.php.*WordPress Manager" | grep -v "wp-cron-wrapper" || true)
        if [ -z "$has_old_jobs" ]; then
            remove_wp_cron_wrapper
        fi
        return 0
    fi

    # Read sites from tracking file
    local tracked_sites=()
    if [ -f "$CRON_JOBS_FILE" ]; then
        while IFS=: read -r domain docroot || [ -n "$domain" ]; do
            if [ -n "$domain" ] && [ -n "$docroot" ]; then
                tracked_sites+=("${domain}:${docroot}")
            fi
        done < "$CRON_JOBS_FILE"
    fi

    # Check each tracked site
    for site in "${tracked_sites[@]}"; do
        IFS=: read -r domain docroot <<< "$site"

        if [ -z "$domain" ] || [ -z "$docroot" ]; then
            continue
        fi

        # Check if wp-config.php has DISABLE_WP_CRON define
        local wp_config=""
        local should_remove=false

        if [ -f "$docroot/wp-config.php" ]; then
            wp_config="$docroot/wp-config.php"
            if ! grep -q "BEGIN WP-Cron Disable - WordPress Manager" "$wp_config" 2>/dev/null; then
                should_remove=true
            fi
        else
            should_remove=true
        fi

        if [ "$should_remove" = true ]; then
            remove_wp_cron_job "$domain"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Removed orphan cron job for $domain" >> "${CONFIG_DIR}/wp-cron-cleanup.log" 2>/dev/null || true
            ((cleaned++))
        fi
    done

    if [ $cleaned -gt 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaned up $cleaned orphan cron job(s)" >> "${CONFIG_DIR}/wp-cron-cleanup.log" 2>/dev/null || true
    fi

    return 0
}

# Setup cleanup cron job (runs daily at 2 AM)
setup_cleanup_cron_job() {
    local cleanup_script="${CONFIG_DIR}/cleanup-orphan-cron.sh"
    local cleanup_cron_cmd="0 2 * * * /bin/bash \"$cleanup_script\" >/dev/null 2>&1"
    local cleanup_cron_comment="# WP-Cron Cleanup - WordPress Manager"

    # Create cleanup script
    mkdir -p "$(dirname "$cleanup_script")" 2>/dev/null || true
    cat > "$cleanup_script" << 'EOF'
#!/bin/bash
# Auto-generated cleanup script for orphan WP-Cron jobs
# This script is managed by WordPress Manager - wp-cron-disable module

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
CRON_JOBS_FILE="${CONFIG_DIR}/wp-cron-jobs.txt"

# Source the module to get cleanup function
MODULE_FILE="${SCRIPT_DIR}/modules/wp-cron-disable.sh"
if [ -f "$MODULE_FILE" ]; then
    source "$MODULE_FILE" 2>/dev/null || true
fi

# Run cleanup
cleanup_orphan_cron_jobs
EOF
    chmod +x "$cleanup_script" 2>/dev/null || true

    # Check if cleanup cron job already exists
    if crontab -l 2>/dev/null | grep -q "WP-Cron Cleanup - WordPress Manager"; then
        return 1  # Already exists
    fi

    # Add cleanup cron job to crontab
    (crontab -l 2>/dev/null; echo "$cleanup_cron_cmd $cleanup_cron_comment") | crontab - 2>/dev/null

    return $?
}

# Remove cleanup cron job
remove_cleanup_cron_job() {
    crontab -l 2>/dev/null | grep -v "WP-Cron Cleanup - WordPress Manager" | crontab - 2>/dev/null
}

# Enable WP-Cron disabling (disable auto cron, enable system cron)
wp-cron-disable_enable() {
    print_info "Disabling WP-Cron auto execution and setting up system cron (every 15 minutes)..."

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

    # Cleanup orphan cron jobs before processing (immediate cleanup)
    print_info "Checking for orphan cron jobs..."
    cleanup_orphan_cron_jobs

    # Setup automatic cleanup cron job (runs daily at 2 AM)
    if setup_cleanup_cron_job; then
        print_info "Automatic cleanup cron job configured (runs daily at 2:00 AM)"
    fi

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

        # Generate the block content once
        local block_content="
/* BEGIN WP-Cron Disable - WordPress Manager
 * Added on $(date '+%Y-%m-%d %H:%M:%S')
 * WP-Cron auto execution disabled. System cron runs wp-cron.php every 15 minutes.
 */
define('DISABLE_WP_CRON', true);
/* END WP-Cron Disable - WordPress Manager */"

        if [ "$has_existing_define" = true ]; then
            # Replace existing define with managed block
            {
                head -n $((existing_define_line - 1)) "$wp_config"
                echo "$block_content"
                tail -n +$((existing_define_line + 1)) "$wp_config"
            } > "$temp_file"
        else
            # Find the insertion point (before "/* That's all, stop editing! */" or at end of file)
            local insert_line
            local total_lines=$(wc -l < "$wp_config" | tr -d ' ')

            if grep -q "That's all, stop editing" "$wp_config" 2>/dev/null; then
                insert_line=$(grep -n "That's all, stop editing" "$wp_config" | head -1 | cut -d: -f1)
            else
                insert_line=$((total_lines + 1))
            fi

            # Insert the define statement with BEGIN/END comments
            if [ $insert_line -gt $total_lines ]; then
                # Insert at the end
                {
                    cat "$wp_config"
                    echo "$block_content"
                } > "$temp_file"
            else
                # Insert before the "That's all" comment
                {
                    head -n $((insert_line - 1)) "$wp_config"
                    echo "$block_content"
                    tail -n +$insert_line "$wp_config"
                } > "$temp_file"
            fi
        fi

        # Replace original file
        if mv "$temp_file" "$wp_config" 2>/dev/null; then
            # Restore ownership if possible
            chown webapps:webapps "$wp_config" 2>/dev/null || true
            chmod 644 "$wp_config" 2>/dev/null || true

            # Add system cron job (runs every 15 minutes)
            if add_wp_cron_job "$domain" "$docroot"; then
                print_success "Disabled WP-Cron auto execution and added system cron for $domain"
                ((count++))
            else
                print_warning "WP-Cron disabled in wp-config.php but cron job already exists for $domain"
                ((count++))
            fi
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
    print_info "All sites will run via single system cron job (every 15 minutes)"

    if [ $failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Disable WP-Cron disabling (remove the define and system cron)
wp-cron-disable_disable() {
    print_info "Re-enabling WP-Cron auto execution and removing system cron jobs..."

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

            # Remove system cron job
            remove_wp_cron_job "$domain"

            print_success "Re-enabled WP-Cron auto execution and removed system cron for $domain"
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
    print_info "Re-enabled WP-Cron auto execution and removed system cron jobs"

    # Remove cleanup cron job if no more WP-Cron jobs exist
    if [ ! -f "$CRON_JOBS_FILE" ] || [ ! -s "$CRON_JOBS_FILE" ]; then
        remove_cleanup_cron_job
        print_info "Removed automatic cleanup cron job (no WP-Cron jobs remaining)"
    fi

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

        local has_define=false
        local has_cron=false

        if [ -f "$wp_config" ] && grep -q "BEGIN WP-Cron Disable - WordPress Manager" "$wp_config" 2>/dev/null; then
            has_define=true
        fi

        # Check if site is in tracking file (new method) or has individual cron job (old method)
        local in_tracking=false
        if [ -f "$CRON_JOBS_FILE" ] && grep -q "^${domain}:" "$CRON_JOBS_FILE" 2>/dev/null; then
            in_tracking=true
        fi

        # Check for wrapper cron job
        local has_wrapper_cron=false
        if crontab -l 2>/dev/null | grep -q "wp-cron-wrapper.sh.*WordPress Manager"; then
            has_wrapper_cron=true
        fi

        # Check for old individual cron job (for backward compatibility)
        local has_old_cron=false
        if crontab -l 2>/dev/null | grep -q "wp-cron.php.*${domain}.*WordPress Manager"; then
            has_old_cron=true
        fi

        if [ "$has_define" = true ] && [ "$in_tracking" = true ] && [ "$has_wrapper_cron" = true ]; then
            echo -e "  ${GREEN}✓${NC} $domain - WP-Cron Disabled (System Cron Active)"
            ((disabled++))
        elif [ "$has_define" = true ] && [ "$in_tracking" = true ]; then
            echo -e "  ${YELLOW}⚠${NC} $domain - WP-Cron Disabled (Wrapper Cron Missing)"
            ((disabled++))
        elif [ "$has_define" = true ]; then
            echo -e "  ${YELLOW}⚠${NC} $domain - WP-Cron Disabled (Not in tracking file)"
            ((disabled++))
        elif [ "$has_old_cron" = true ] || [ "$in_tracking" = true ]; then
            echo -e "  ${YELLOW}⚠${NC} $domain - Orphan Cron Job (WP-Cron Not Disabled - will be cleaned up)"
            ((enabled++))
        else
            echo -e "  ${RED}✗${NC} $domain - WP-Cron Enabled (Auto)"
            ((enabled++))
        fi

    done

    echo ""
    echo "Summary:"
    echo "  Total WordPress sites: $total"
    echo -e "  ${GREEN}WP-Cron Disabled: $disabled${NC}"
    echo -e "  ${RED}WP-Cron Enabled: $enabled${NC}"
    echo ""
    if [ $enabled -gt 0 ]; then
        print_info "Note: Orphan cron jobs (cron without define) will be automatically cleaned up when you enable/disable this module"
    fi
}

###############################################################################
# Note: This module uses utility functions from main script
# Functions like print_info, print_success, get_wordpress_sites are available
# from the main script when this module is loaded via 'source'
###############################################################################

