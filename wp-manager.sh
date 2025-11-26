#!/bin/bash

###############################################################################
# WordPress Manager for DirectAdmin + Apache
# Main script with modular architecture
###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
CONFIG_DIR="$SCRIPT_DIR/config"
CACHE_DIR="$SCRIPT_DIR/cache"

# Create necessary directories
mkdir -p "$MODULES_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$CACHE_DIR"

# Cache file for WordPress sites
WP_SITES_CACHE="$CACHE_DIR/wordpress_sites.txt"
WP_SITES_CACHE_TIMESTAMP="$CACHE_DIR/wordpress_sites.timestamp"

# DirectAdmin paths
DA_USERDATA="/usr/local/directadmin/data/users"
DA_HTTPD_CONF="/etc/httpd/conf/extra/httpd-includes.conf"
HOME_DIR="/home"

###############################################################################
# Utility Functions
###############################################################################

# Print colored message
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

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "Please run as root"
        exit 1
    fi
}

# Scan and cache WordPress sites
scan_wordpress_sites() {
    local force_rescan="${1:-false}"
    
    # Check if cache exists and is valid (not older than 24 hours by default)
    if [ "$force_rescan" != "true" ] && [ -f "$WP_SITES_CACHE" ] && [ -f "$WP_SITES_CACHE_TIMESTAMP" ]; then
        local cache_age=$(($(date +%s) - $(cat "$WP_SITES_CACHE_TIMESTAMP")))
        local max_age=86400  # 24 hours in seconds
        
        if [ $cache_age -lt $max_age ]; then
            print_info "Using cached WordPress sites list (age: $(($cache_age / 3600))h)"
            return 0
        else
            print_info "Cache expired, rescanning..."
        fi
    fi
    
    print_info "Scanning for WordPress sites..."
    
    local sites=()
    local total_domains=0
    local wp_sites=0
    
    # Scan from /home directory (DirectAdmin structure)
    if [ -d "$HOME_DIR" ]; then
        print_info "Scanning $HOME_DIR directory..."
        
        # Find all user directories in /home
        for user_dir in "$HOME_DIR"/*; do
            if [ -d "$user_dir" ]; then
                local user_name=$(basename "$user_dir")
                local domains_dir="$user_dir/domains"
                
                if [ -d "$domains_dir" ]; then
                    # Find all domain directories
                    for domain_dir in "$domains_dir"/*; do
                        if [ -d "$domain_dir" ]; then
                            local domain=$(basename "$domain_dir")
                            local docroot="$domain_dir/public_html"
                            
                            if [ -d "$docroot" ]; then
                                ((total_domains++))
                                
                                # Check if WordPress exists (look for wp-config.php)
                                if [ -f "$docroot/wp-config.php" ]; then
                                    sites+=("$domain:$docroot")
                                    ((wp_sites++))
                                fi
                            fi
                        fi
                    done
                fi
            fi
        done
    else
        print_warning "Home directory not found: $HOME_DIR, trying DirectAdmin userdata..."
    fi
    
    # Also try DirectAdmin userdata if exists (for compatibility or fallback)
    if [ -d "$DA_USERDATA" ]; then
        if [ ${#sites[@]} -eq 0 ]; then
            print_info "Scanning DirectAdmin userdata..."
        else
            print_info "Also scanning DirectAdmin userdata for additional sites..."
        fi
        
        for user_dir in "$DA_USERDATA"/*; do
            if [ -d "$user_dir" ]; then
                local domains_file="$user_dir/domains.list"
                if [ -f "$domains_file" ]; then
                    while IFS= read -r domain; do
                        if [ -n "$domain" ]; then
                            # Check if already found in /home
                            local found=false
                            for site in "${sites[@]}"; do
                                if [[ "$site" == "$domain:"* ]]; then
                                    found=true
                                    break
                                fi
                            done
                            
                            if [ "$found" = false ]; then
                                ((total_domains++))
                                # Check if WordPress exists (look for wp-config.php)
                                local docroot="$user_dir/domains/$domain/public_html"
                                if [ -f "$docroot/wp-config.php" ]; then
                                    sites+=("$domain:$docroot")
                                    ((wp_sites++))
                                fi
                            fi
                        fi
                    done < "$domains_file"
                fi
            fi
        done
    fi
    
    # If no sites found in both locations, return error
    if [ ${#sites[@]} -eq 0 ] && [ ! -d "$HOME_DIR" ] && [ ! -d "$DA_USERDATA" ]; then
        print_error "Neither $HOME_DIR nor $DA_USERDATA found. Cannot scan for WordPress sites."
        return 1
    fi
    
    # Save to cache file
    if [ ${#sites[@]} -gt 0 ]; then
        printf '%s\n' "${sites[@]}" > "$WP_SITES_CACHE"
        echo $(date +%s) > "$WP_SITES_CACHE_TIMESTAMP"
        print_success "Found $wp_sites WordPress site(s) out of $total_domains total domain(s)"
        print_info "Cache saved to $WP_SITES_CACHE"
    else
        # Create empty cache file
        touch "$WP_SITES_CACHE"
        echo $(date +%s) > "$WP_SITES_CACHE_TIMESTAMP"
        print_warning "No WordPress sites found"
    fi
    
    return 0
}

# Load WordPress sites from cache
load_wordpress_sites_cache() {
    if [ ! -f "$WP_SITES_CACHE" ]; then
        return 1
    fi
    
    cat "$WP_SITES_CACHE"
    return 0
}

# Get all WordPress sites (from cache or scan)
get_wordpress_sites() {
    local force_rescan="${1:-false}"
    
    # Try to load from cache first
    if [ "$force_rescan" != "true" ] && [ -f "$WP_SITES_CACHE" ]; then
        local cached_sites=$(load_wordpress_sites_cache)
        if [ -n "$cached_sites" ]; then
            printf '%s\n' "$cached_sites"
            return 0
        fi
    fi
    
    # If cache doesn't exist or force rescan, scan and return
    scan_wordpress_sites "$force_rescan" > /dev/null 2>&1
    load_wordpress_sites_cache
}

# Count WordPress sites
count_wordpress_sites() {
    local count=$(get_wordpress_sites | wc -l)
    # Remove trailing whitespace
    echo $count
}

###############################################################################
# Module Management
###############################################################################

# Load module
load_module() {
    local module_name="$1"
    local module_file="$MODULES_DIR/${module_name}.sh"
    
    if [ ! -f "$module_file" ]; then
        print_error "Module not found: $module_name"
        return 1
    fi
    
    source "$module_file"
}

# Get module status
get_module_status() {
    local module_name="$1"
    local status_file="$CONFIG_DIR/${module_name}.status"
    
    if [ -f "$status_file" ]; then
        cat "$status_file"
    else
        echo "disabled"
    fi
}

# Set module status
set_module_status() {
    local module_name="$1"
    local status="$2"
    local status_file="$CONFIG_DIR/${module_name}.status"
    
    echo "$status" > "$status_file"
}

# List available modules
list_modules() {
    local modules=()
    for module_file in "$MODULES_DIR"/*.sh; do
        if [ -f "$module_file" ]; then
            local module_name=$(basename "$module_file" .sh)
            modules+=("$module_name")
        fi
    done
    
    printf '%s\n' "${modules[@]}"
}

###############################################################################
# Menu System
###############################################################################

show_main_menu() {
    clear
    echo "=========================================="
    echo "  WordPress Manager for DirectAdmin"
    echo "=========================================="
    echo ""
    
    # Check cache status
    local cache_info=""
    if [ -f "$WP_SITES_CACHE_TIMESTAMP" ]; then
        local cache_age=$(($(date +%s) - $(cat "$WP_SITES_CACHE_TIMESTAMP")))
        local cache_hours=$(($cache_age / 3600))
        local cache_mins=$((($cache_age % 3600) / 60))
        if [ $cache_hours -eq 0 ]; then
            cache_info=" (cache: ${cache_mins}m ago)"
        else
            cache_info=" (cache: ${cache_hours}h ${cache_mins}m ago)"
        fi
    fi
    
    local wp_count=$(count_wordpress_sites)
    print_info "Found $wp_count WordPress sites$cache_info"
    echo ""
    
    echo "Available Modules:"
    echo "-------------------"
    
    local modules=($(list_modules))
    local index=1
    
    for module in "${modules[@]}"; do
        local status=$(get_module_status "$module")
        local status_color=""
        local status_text=""
        
        if [ "$status" == "enabled" ]; then
            status_color="$GREEN"
            status_text="[ENABLED]"
        else
            status_color="$RED"
            status_text="[DISABLED]"
        fi
        
        # Get module description if available
        local description=""
        if type "${module}_description" &>/dev/null; then
            description=$("${module}_description")
        else
            description="$module"
        fi
        
        echo -e "  $index) $description ${status_color}${status_text}${NC}"
        ((index++))
    done
    
    echo ""
    echo "  r) Rescan WordPress sites"
    echo "  0) Exit"
    echo ""
    echo -n "Select option: "
}

handle_module_menu() {
    local module_name="$1"
    local status=$(get_module_status "$module_name")
    
    clear
    echo "=========================================="
    echo "  Module: $module_name"
    echo "=========================================="
    echo ""
    
    if [ "$status" == "enabled" ]; then
        echo -e "Current Status: ${GREEN}ENABLED${NC}"
    else
        echo -e "Current Status: ${RED}DISABLED${NC}"
    fi
    echo ""
    echo "Options:"
    echo "  1) Enable"
    echo "  2) Disable"
    echo "  3) Status"
    echo "  0) Back to main menu"
    echo ""
    echo -n "Select option: "
    
    read choice
    
    case $choice in
        1)
            print_info "Enabling $module_name..."
            if "${module_name}_enable"; then
                set_module_status "$module_name" "enabled"
                print_success "$module_name enabled successfully"
            else
                print_error "Failed to enable $module_name"
            fi
            echo ""
            read -p "Press Enter to continue..."
            ;;
        2)
            print_info "Disabling $module_name..."
            if "${module_name}_disable"; then
                set_module_status "$module_name" "disabled"
                print_success "$module_name disabled successfully"
            else
                print_error "Failed to disable $module_name"
            fi
            echo ""
            read -p "Press Enter to continue..."
            ;;
        3)
            print_info "Checking status of $module_name..."
            "${module_name}_status"
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
}

main_loop() {
    # Initial scan on startup
    scan_wordpress_sites false
    
    while true; do
        show_main_menu
        read choice
        
        if [ -z "$choice" ]; then
            continue
        fi
        
        if [ "$choice" == "0" ]; then
            print_info "Goodbye!"
            exit 0
        fi
        
        # Handle rescan option
        if [ "$choice" == "r" ] || [ "$choice" == "R" ]; then
            print_info "Rescanning WordPress sites..."
            scan_wordpress_sites true
            echo ""
            read -p "Press Enter to continue..."
            continue
        fi
        
        local modules=($(list_modules))
        local module_index=$((choice - 1))
        
        if [ "$module_index" -ge 0 ] && [ "$module_index" -lt "${#modules[@]}" ]; then
            local selected_module="${modules[$module_index]}"
            load_module "$selected_module"
            handle_module_menu "$selected_module"
        else
            print_error "Invalid option"
            sleep 2
        fi
    done
}

###############################################################################
# Main Entry Point
###############################################################################

main() {
    check_root
    
    # Check if DirectAdmin is installed
    if [ ! -d "$DA_USERDATA" ]; then
        print_error "DirectAdmin not found. Please check your installation."
        exit 1
    fi
    
    # Start main loop
    main_loop
}

# Run main function
main "$@"

