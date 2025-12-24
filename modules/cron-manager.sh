#!/bin/bash

###############################################################################
# Cron Manager Module
# Manage system cron jobs (view, edit, add, delete, backup, restore)
###############################################################################

# Module name
MODULE_NAME="cron-manager"

# Get config directory (use from main script if available, otherwise calculate)
if [ -z "$CONFIG_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    CONFIG_DIR="${SCRIPT_DIR}/config"
fi

###############################################################################
# Module Functions
###############################################################################

cron_manager_description() {
    echo "Manage Cron Jobs"
}

# Show and manage cron jobs
show_cron_jobs() {
    local cron_list=$(crontab -l 2>/dev/null)

    if [ -z "$cron_list" ]; then
        print_warning "No cron jobs found"
        return 1
    fi

    echo "Current Cron Jobs:"
    echo "=================="
    echo ""

    # Show cron jobs with line numbers
    local line_num=1
    while IFS= read -r line; do
        # Skip empty lines and comments (but show them for reference)
        if [[ "$line" =~ ^#.* ]]; then
            echo -e "${BLUE}  $line_num) $line${NC}"
        elif [ -n "$line" ]; then
            echo -e "  ${GREEN}$line_num)${NC} $line"
        else
            echo ""
        fi
        ((line_num++))
    done <<< "$cron_list"

    return 0
}

# Handle cron jobs management menu
cron_manager_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "  Cron Jobs Management"
        echo "=========================================="
        echo ""

        show_cron_jobs
        echo ""
        echo "Options:"
        echo "  1) Edit cron jobs (using editor)"
        echo "  2) Delete a cron job"
        echo "  3) Add new cron job"
        echo "  4) Backup current crontab"
        echo "  5) Restore from backup"
        echo "  0) Back to main menu"
        echo ""
        echo -n "Select option: "

        read choice

        case $choice in
            1)
                # Edit crontab using editor
                local temp_cron=$(mktemp)
                crontab -l 2>/dev/null > "$temp_cron" || touch "$temp_cron"

                # Use vi or nano, prefer nano if available
                if command -v nano &> /dev/null; then
                    nano "$temp_cron"
                elif command -v vi &> /dev/null; then
                    vi "$temp_cron"
                else
                    print_error "No editor found (nano or vi required)"
                    rm -f "$temp_cron"
                    read -p "Press Enter to continue..."
                    continue
                fi

                # Install edited crontab
                if crontab "$temp_cron" 2>/dev/null; then
                    print_success "Cron jobs updated successfully"
                else
                    print_error "Failed to update cron jobs. Invalid syntax?"
                fi
                rm -f "$temp_cron"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                # Delete a cron job
                echo ""
                echo -n "Enter line number to delete: "
                read line_num

                if ! [[ "$line_num" =~ ^[0-9]+$ ]]; then
                    print_error "Invalid line number"
                    sleep 2
                    continue
                fi

                local temp_cron=$(mktemp)
                local temp_cron_new=$(mktemp)
                crontab -l 2>/dev/null > "$temp_cron" || touch "$temp_cron"

                # Check if line number is valid
                local total_lines=$(wc -l < "$temp_cron" | tr -d ' ')
                if [ "$line_num" -lt 1 ] || [ "$line_num" -gt "$total_lines" ]; then
                    print_error "Line number out of range (1-$total_lines)"
                    rm -f "$temp_cron" "$temp_cron_new"
                    sleep 2
                    continue
                fi

                # Use sed to delete the line (try -i first, fallback to temp file)
                if sed -i "${line_num}d" "$temp_cron" 2>/dev/null; then
                    # Success with -i flag
                    :
                elif sed "${line_num}d" "$temp_cron" > "$temp_cron_new" 2>/dev/null; then
                    # Success with output redirection
                    mv "$temp_cron_new" "$temp_cron" 2>/dev/null || {
                        print_error "Failed to process cron file"
                        rm -f "$temp_cron" "$temp_cron_new"
                        sleep 2
                        continue
                    }
                else
                    print_error "Failed to delete line $line_num"
                    rm -f "$temp_cron" "$temp_cron_new"
                    sleep 2
                    continue
                fi

                if crontab "$temp_cron" 2>/dev/null; then
                    print_success "Cron job deleted successfully"
                    sleep 1
                else
                    print_error "Failed to delete cron job"
                    echo ""
                    read -p "Press Enter to continue..."
                fi
                rm -f "$temp_cron" "$temp_cron_new"
                ;;
            3)
                # Add new cron job
                echo ""
                echo "Enter new cron job (format: minute hour day month weekday command):"
                echo "Example: */15 * * * * /usr/bin/curl -s https://example.com/wp-cron.php"
                echo ""
                echo -n "Cron schedule (minute hour day month weekday): "
                read schedule

                if [ -z "$schedule" ]; then
                    print_error "Schedule cannot be empty"
                    sleep 2
                    continue
                fi

                echo -n "Command to run: "
                read command

                if [ -z "$command" ]; then
                    print_error "Command cannot be empty"
                    sleep 2
                    continue
                fi

                # Validate schedule format (basic check - 5 fields)
                local field_count=$(echo "$schedule" | awk '{print NF}')
                if [ $field_count -ne 5 ]; then
                    print_error "Invalid schedule format. Must have 5 fields: minute hour day month weekday"
                    sleep 2
                    continue
                fi

                # Add to crontab
                (crontab -l 2>/dev/null; echo "$schedule $command") | crontab - 2>/dev/null

                if [ $? -eq 0 ]; then
                    print_success "Cron job added successfully"
                else
                    print_error "Failed to add cron job"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                # Backup crontab
                local backup_file="${CONFIG_DIR}/crontab.backup.$(date +%Y%m%d_%H%M%S)"
                crontab -l 2>/dev/null > "$backup_file"

                if [ $? -eq 0 ]; then
                    print_success "Crontab backed up to: $backup_file"
                else
                    print_error "Failed to backup crontab"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                # Restore from backup
                local backups=($(ls -t "${CONFIG_DIR}"/crontab.backup.* 2>/dev/null))

                if [ ${#backups[@]} -eq 0 ]; then
                    print_error "No backup files found"
                    sleep 2
                    continue
                fi

                echo ""
                echo "Available backups:"
                local idx=1
                for backup in "${backups[@]}"; do
                    local backup_name=$(basename "$backup")
                    local backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 || echo "unknown")
                    echo "  $idx) $backup_name ($backup_date)"
                    ((idx++))
                done
                echo ""
                echo -n "Select backup to restore (1-${#backups[@]}): "
                read backup_choice

                if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt ${#backups[@]} ]; then
                    print_error "Invalid selection"
                    sleep 2
                    continue
                fi

                local selected_backup="${backups[$((backup_choice - 1))]}"

                echo ""
                echo -n "Are you sure you want to restore from $selected_backup? (y/N): "
                read confirm

                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    print_info "Restore cancelled"
                    sleep 2
                    continue
                fi

                if crontab "$selected_backup" 2>/dev/null; then
                    print_success "Crontab restored successfully"
                else
                    print_error "Failed to restore crontab"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 2
                ;;
        esac
    done
}

# Enable/Disable/Status functions (required by module system but not used for this module)
cron_manager_enable() {
    print_info "Cron Manager is always available. Use the menu option to manage cron jobs."
    return 0
}

cron_manager_disable() {
    print_info "Cron Manager cannot be disabled. Use the menu option to manage cron jobs."
    return 0
}

cron_manager_status() {
    print_info "Cron Jobs Status:"
    echo ""
    show_cron_jobs
    echo ""
    local cron_count=$(crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | wc -l)
    echo "Total active cron jobs: $cron_count"
}

###############################################################################
# Note: This module uses utility functions from main script
# Functions like print_info, print_success, get_wordpress_sites are available
# from the main script when this module is loaded via 'source'
###############################################################################

