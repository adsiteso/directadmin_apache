#!/bin/bash

###############################################################################
# Format Script - Convert line endings from CRLF to LF
# This script converts all .sh files from Windows line endings to Unix
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "=========================================="
echo "  Format Script - Line Endings Converter"
echo "=========================================="
echo ""

# Check if dos2unix is available
if command -v dos2unix &> /dev/null; then
    echo "[INFO] Using dos2unix to convert line endings..."
    echo ""
    
    # Convert all .sh files
    find . -name "*.sh" -type f | while read -r file; do
        if dos2unix "$file" 2>/dev/null; then
            echo "[OK] Converted: $file"
        else
            echo "[ERROR] Failed to convert: $file"
        fi
    done
elif command -v sed &> /dev/null; then
    echo "[INFO] Using sed to convert line endings..."
    echo ""
    
    # Convert all .sh files using sed
    find . -name "*.sh" -type f | while read -r file; do
        if sed -i 's/\r$//' "$file" 2>/dev/null; then
            echo "[OK] Converted: $file"
        else
            echo "[ERROR] Failed to convert: $file"
        fi
    done
else
    echo "[ERROR] Neither dos2unix nor sed found. Cannot convert line endings."
    exit 1
fi

echo ""
echo "=========================================="
echo "[SUCCESS] All .sh files have been converted to Unix line endings (LF)"
echo "=========================================="

