#!/bin/bash

# ranger-repomix-integration.sh
# This script helps integrate ranger file manager with repomix

# Check if ranger is installed
if ! command -v ranger &> /dev/null; then
    echo "Ranger is not installed. Install it first."
    exit 1
fi

# Check if repomix is installed
if ! command -v repomix &> /dev/null && ! npm list -g repomix &> /dev/null; then
    echo "Repomix is not installed. Install it with 'npm install -g repomix' first."
    exit 1
fi

# Create a temporary rc.conf for ranger
TEMP_RC_CONF="/tmp/ranger_repomix_rc.conf"
SELECTED_FILES="/tmp/repomix_selected_files.txt"

# Clean up any existing file
rm -f "$SELECTED_FILES"
touch "$SELECTED_FILES"

# Create ranger configuration for file selection
cat > "$TEMP_RC_CONF" << 'EOF'
# Repomix integration for ranger

# Mark files with space and save to repomix selection file
map <space> chain mark_files toggle=True; shell echo %p >> /tmp/repomix_selected_files.txt

# Custom command to run repomix with selected files
map ,r shell cat /tmp/repomix_selected_files.txt | sort | uniq | tr '\n' ',' | xargs -I{} repomix --include "{}"

# Show help information
map ,h shell echo "Repomix Integration Help:\n\n<space> - Mark/unmark file for inclusion\n,r - Run repomix with selected files\n,h - Show this help\n,c - Clear selection" | less

# Clear selection
map ,c shell rm -f /tmp/repomix_selected_files.txt && touch /tmp/repomix_selected_files.txt && echo "Selection cleared"
EOF

# Launch ranger with the custom configuration
echo "=== Ranger-Repomix Integration ==="
echo "Use <space> to select files for repomix"
echo "Press ,r to run repomix with selected files"
echo "Press ,h for help"
echo "Press ,c to clear selection"
echo "===============================>"

ranger --cmd="source $TEMP_RC_CONF"

# Clean up
echo "Cleaning up temporary files..."
rm -f "$TEMP_RC_CONF"

# Check if any files were selected and not processed
if [ -s "$SELECTED_FILES" ]; then
    echo "You still have selected files that were not processed."
    echo "Would you like to run repomix with these files? (y/n)"
    read -r answer
    
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        # Get unique files and convert to comma-separated list
        INCLUDE_LIST=$(cat "$SELECTED_FILES" | sort | uniq | tr '\n' ',')
        # Remove trailing comma
        INCLUDE_LIST=${INCLUDE_LIST%,}
        
        echo "Running: repomix --include \"$INCLUDE_LIST\""
        repomix --include "$INCLUDE_LIST"
    fi
fi

# Final cleanup
rm -f "$SELECTED_FILES"
echo "Done."