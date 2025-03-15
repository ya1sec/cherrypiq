#!/bin/bash

# fix-cherrypiq.sh
# This script fixes a broken cherrypiq installation

echo "Fixing cherrypiq installation..."

# First, uninstall the broken installation
echo "Step 1: Uninstalling broken cherrypiq..."

# Remove the broken symlink
if [ -f /opt/homebrew/bin/cherrypiq ]; then
    echo "Removing broken symlink at /opt/homebrew/bin/cherrypiq..."
    sudo rm -f /opt/homebrew/bin/cherrypiq
fi

# Remove global npm link
echo "Removing global npm link..."
npm unlink -g cherrypiq 2>/dev/null || npm uninstall -g cherrypiq 2>/dev/null

# Remove ranger integration if it exists
if [ -f /usr/local/bin/ranger-repomix ]; then
    echo "Removing ranger integration..."
    sudo rm -f /usr/local/bin/ranger-repomix 2>/dev/null
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
npm install -g repomix

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

# Copy the local cherrypiq.js file
echo "Copying cherrypiq script..."
# Check for different possible filenames
if [ -f "./cherrypiq.js" ]; then
    cp ./cherrypiq.js ~/.cherrypiq/cherrypiq.js
    echo "Copied local cherrypiq.js script"
elif [ -f "./cherrypick.js" ]; then
    cp ./cherrypick.js ~/.cherrypiq/cherrypiq.js
    echo "Copied local cherrypick.js script"
elif [ -f "./index.js" ]; then
    cp ./index.js ~/.cherrypiq/cherrypiq.js
    echo "Copied local index.js script"
else
    echo "Error: Could not find cherrypiq script file."
    echo "Please make sure you're running this script from the cherrypiq repository directory."
    echo "Looking for one of these files: cherrypiq.js, cherrypick.js, or index.js"
    exit 1
fi

# Make the script executable
chmod +x ~/.cherrypiq/cherrypiq.js

# Install local dependencies
echo "Installing local dependencies..."
cd ~/.cherrypiq && npm install

# Create global symlink
echo "Creating global symlink..."
cd ~/.cherrypiq && npm link

# Copy ranger integration script if ranger is installed
if command -v ranger &> /dev/null; then
    echo "Ranger detected, installing ranger integration..."
    if [ -f "./ranger-integration.sh" ]; then
        cp ./ranger-integration.sh ~/.cherrypiq/ranger-repomix-integration.sh
        chmod +x ~/.cherrypiq/ranger-repomix-integration.sh
        sudo ln -sf ~/.cherrypiq/ranger-repomix-integration.sh /usr/local/bin/ranger-repomix || {
            echo "Failed to create global symlink for ranger integration. You may need sudo:"
            echo "sudo ln -sf ~/.cherrypiq/ranger-repomix-integration.sh /usr/local/bin/ranger-repomix"
        }
    else
        echo "Warning: Could not find ranger-integration.sh file. Ranger integration will not be available."
    fi
fi

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