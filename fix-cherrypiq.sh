#!/bin/bash

# fix-cherrypiq.sh
# This script fixes a broken cherrypiq installation

# Save the current directory
ORIGINAL_DIR=$(pwd)

echo "Fixing cherrypiq installation..."

# First, uninstall the broken installation
echo "Step 1: Uninstalling broken cherrypiq..."

# Remove any existing symlinks in common paths
for path in "/opt/homebrew/bin/cherrypiq" "/usr/local/bin/cherrypiq" "/usr/bin/cherrypiq"; do
    if [ -f "$path" ]; then
        echo "Removing symlink at $path..."
        sudo rm -f "$path" 2>/dev/null || {
            echo "Failed to remove symlink at $path. You may need to remove it manually:"
            echo "sudo rm -f $path"
        }
    fi
done

# Remove global npm link
echo "Removing global npm link..."
npm unlink -g cherrypiq 2>/dev/null || npm uninstall -g cherrypiq 2>/dev/null

# Remove ranger integration if it exists
if [ -f /usr/local/bin/ranger-repomix ]; then
    echo "Removing ranger integration..."
    sudo rm -f /usr/local/bin/ranger-repomix 2>/dev/null || {
        echo "Failed to remove ranger integration symlink. You may need to remove it manually:"
        echo "sudo rm -f /usr/local/bin/ranger-repomix"
    }
fi

# Remove cherrypiq directory
echo "Removing cherrypiq files..."
if [ -d ~/.cherrypiq ]; then
    rm -rf ~/.cherrypiq
    echo "Removed ~/.cherrypiq directory"
fi

# Now reinstall using local files
echo "Step 2: Reinstalling cherrypiq from local files..."

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

# Install required packages globally
echo "Installing global dependencies..."
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

# Install local dependencies
echo "Installing local dependencies..."
(cd ~/.cherrypiq && npm install)

# Copy the local cherrypiq.js file or download from GitHub if not found
echo "Setting up cherrypiq script..."
if [ -f "./cherrypiq.js" ] || [ -f "./cherrypiq.js" ] || [ -f "./index.js" ]; then
    # Try to copy from local files
    if [ -f "./cherrypiq.js" ]; then
        cp ./cherrypiq.js ~/.cherrypiq/cherrypiq.js
        echo "Copied local cherrypiq.js script"
    elif [ -f "./cherrypiq.js" ]; then
        cp ./cherrypiq.js ~/.cherrypiq/cherrypiq.js
        echo "Copied local cherrypiq.js script"
    elif [ -f "./index.js" ]; then
        cp ./index.js ~/.cherrypiq/cherrypiq.js
        echo "Copied local index.js script"
    fi
else
    # If no local file found, download from GitHub
    echo "No local script found, downloading from GitHub..."
    curl -o ~/.cherrypiq/cherrypiq.js https://raw.githubusercontent.com/ya1sec/cherrypiq/main/cherrypiq.js || {
        echo "Error: Failed to download script from GitHub."
        echo "Please ensure you're running this script from the cherrypiq repository directory"
        echo "or have an internet connection to download from GitHub."
        exit 1
    }
fi

# Make the script executable
chmod +x ~/.cherrypiq/cherrypiq.js

# Create global symlink
echo "Creating global symlink..."
(cd ~/.cherrypiq && npm link)

# Setup ranger integration if ranger is installed
if command -v ranger &> /dev/null; then
    echo "Ranger detected, installing ranger integration..."
    if [ -f "./ranger-integration.sh" ]; then
        cp ./ranger-integration.sh ~/.cherrypiq/ranger-repomix-integration.sh
    else
        # Download from GitHub if local file not found
        curl -o ~/.cherrypiq/ranger-repomix-integration.sh https://raw.githubusercontent.com/ya1sec/cherrypiq/main/ranger-repomix-integration.sh || {
            echo "Warning: Failed to setup ranger integration."
            echo "You can try setting it up later by running the installation script again."
        }
    fi
    
    if [ -f ~/.cherrypiq/ranger-repomix-integration.sh ]; then
        chmod +x ~/.cherrypiq/ranger-repomix-integration.sh
        sudo ln -sf ~/.cherrypiq/ranger-repomix-integration.sh /usr/local/bin/ranger-repomix || {
            echo "Failed to create global symlink for ranger integration. You may need sudo:"
            echo "sudo ln -sf ~/.cherrypiq/ranger-repomix-integration.sh /usr/local/bin/ranger-repomix"
        }
    fi
fi

# Return to original directory
cd "$ORIGINAL_DIR"

echo "Installation fixed!"
echo "You can now use cherrypiq from anywhere."
echo ""
echo "Commands:"
echo "  cherrypiq    - Launch the interactive file selector"
if command -v ranger &> /dev/null; then
    echo "  ranger-repomix      - Launch ranger with repomix integration"
fi
echo ""
echo "Enjoy!" 