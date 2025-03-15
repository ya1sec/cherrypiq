#!/bin/bash

# install-cherrypiq.sh
# This script installs the cherrypiq tool

# Save the current directory
ORIGINAL_DIR=$(pwd)

echo "Installing cherrypiq..."

# Create directory for the tool
mkdir -p ~/.cherrypiq

# Check if nodejs and npm are installed
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is required but not installed."
    echo "Please install Node.js and npm first, then run this script again."
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo "Error: npm is required but not installed."
    echo "Please install npm first, then run this script again."
    exit 1
fi

# Install required packages
echo "Installing dependencies..."
npm install -g repomix blessed

# Create package.json
cat > ~/.cherrypiq/package.json << 'EOF'
{
  "name": "cherrypiq",
  "version": "0.1.0",
  "description": "Interactive file selector for repomix",
  "main": "cherrypiq.js",
  "bin": {
    "cherrypiq": "./cherrypiq.js"
  },
  "dependencies": {
    "blessed": "^0.1.81"
  }
}
EOF

# Install dependencies in the cherrypiq directory
echo "Installing local dependencies..."
(cd ~/.cherrypiq && npm install)

# Install cherrypiq script
echo "Installing cherrypiq script..."
if [ -f "cherrypiq.js" ]; then
    echo "Using local cherrypiq.js..."
    cp cherrypiq.js ~/.cherrypiq/cherrypiq.js
else
    echo "Local cherrypiq.js not found, downloading from GitHub..."
    curl -o ~/.cherrypiq/cherrypiq.js https://raw.githubusercontent.com/ya1sec/cherrypiq/main/cherrypiq.js || {
        echo "Error: Failed to download cherrypiq.js from GitHub."
        echo "Please ensure you have a local copy of cherrypiq.js or internet connection."
        exit 1
    }
fi

# Make the script executable
chmod +x ~/.cherrypiq/cherrypiq.js

# Create global symlink
echo "Creating global symlink..."
cd ~/.cherrypiq && npm link

# Handle ranger integration if ranger is installed
if command -v ranger &> /dev/null; then
    echo "Ranger detected, installing ranger integration..."
    
    # Create ranger integration directory
    mkdir -p ~/.cherrypiq/ranger

    # Install ranger integration script
    echo "Installing ranger integration script..."
    if [ -f "ranger-repomix.sh" ]; then
        echo "Using local ranger-repomix.sh..."
        cp ranger-repomix.sh ~/.cherrypiq/ranger/ranger-repomix.sh
    else
        echo "Creating ranger integration script..."
        cat > ~/.cherrypiq/ranger/ranger-repomix.sh << 'EOF'
#!/bin/bash

# ranger-repomix.sh
# This script helps integrate ranger file manager with repomix

# Create a temporary rc.conf for ranger
TEMP_RC_CONF="/tmp/ranger_repomix_rc.conf"
SELECTED_FILES="/tmp/repomix_selected_files.txt"

# Clean up any existing file
rm -f "$SELECTED_FILES"
touch "$SELECTED_FILES"

# Create ranger configuration for file selection
cat > "$TEMP_RC_CONF" << 'RANGERCONF'
# Repomix integration for ranger

# Mark files with space and save to repomix selection file
map <space> chain mark_files toggle=True; shell echo %p >> /tmp/repomix_selected_files.txt

# Custom command to run repomix with selected files
map ,r shell cat /tmp/repomix_selected_files.txt | sort | uniq | tr '\n' ',' | xargs -I{} repomix --include "{}"

# Show help information
map ,h shell echo "Repomix Integration Help:\n\n<space> - Mark/unmark file for inclusion\n,r - Run repomix with selected files\n,h - Show this help\n,c - Clear selection" | less

# Clear selection
map ,c shell rm -f /tmp/repomix_selected_files.txt && touch /tmp/repomix_selected_files.txt && echo "Selection cleared"
RANGERCONF

# Launch ranger with the custom configuration
echo "=== Ranger-Repomix Integration ==="
echo "Use <space> to select files for repomix"
echo "Press ,r to run repomix with selected files"
echo "Press ,h for help"
echo "Press ,c to clear selection"
echo "===============================>"

ranger --cmd="source $TEMP_RC_CONF"

# Clean up
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
EOF
    fi

    # Make ranger integration script executable
    chmod +x ~/.cherrypiq/ranger/ranger-repomix.sh

    # Create user-local bin directory if it doesn't exist
    mkdir -p ~/bin

    # Create symlink in user's bin directory
    ln -sf ~/.cherrypiq/ranger/ranger-repomix.sh ~/bin/ranger-repomix
    
    # Add ~/bin to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
        echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
        echo "Added ~/bin to PATH. Please restart your shell or run: source ~/.zshrc (or ~/.bashrc)"
    fi

    echo "Ranger integration installed in ~/bin/ranger-repomix"
fi

# Return to original directory
cd "$ORIGINAL_DIR"

echo "Installation complete!"
echo "You can now use cherrypiq from anywhere."
echo ""
echo "Commands:"
echo "  cherrypiq    - Launch the interactive file selector"
if command -v ranger &> /dev/null; then
    echo "  ranger-repomix      - Launch ranger with repomix integration"
fi
echo ""
echo "Enjoy!"