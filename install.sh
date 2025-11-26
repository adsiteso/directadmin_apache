#!/bin/bash

###############################################################################
# Installation script for WordPress Manager
# Sets proper permissions and creates necessary directories
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing WordPress Manager..."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Error: Please run as root"
    exit 1
fi

# Set executable permissions
echo "Setting executable permissions..."
chmod +x "$SCRIPT_DIR/wp-manager.sh"
chmod +x "$SCRIPT_DIR/modules"/*.sh 2>/dev/null || true

# Create necessary directories
echo "Creating directories..."
mkdir -p "$SCRIPT_DIR/modules"
mkdir -p "$SCRIPT_DIR/config"

echo ""
echo "Installation completed!"
echo ""
echo "To run the manager, execute:"
echo "  sudo $SCRIPT_DIR/wp-manager.sh"
echo ""

