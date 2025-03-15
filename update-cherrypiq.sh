#!/bin/bash

# update-cherrypiq.sh
# This script updates cherrypiq with local changes

echo "Updating cherrypiq with local changes..."

# Save the current directory
ORIGINAL_DIR=$(pwd)

# Check if cherrypiq.js exists in current directory
if [ ! -f "cherrypiq.js" ]; then
    echo "Error: cherrypiq.js not found in current directory."
    echo "Please run this script from the directory containing your modified cherrypiq.js"
    exit 1
fi

# Check if ~/.cherrypiq exists
if [ ! -d ~/.cherrypiq ]; then
    echo "Error: cherrypiq installation directory not found."
    echo "Please install cherrypiq first using install-cherrypiq.sh"
    exit 1
fi

# Copy the local cherrypiq.js to the installation directory
echo "Copying local cherrypiq.js to installation directory..."
cp cherrypiq.js ~/.cherrypiq/cherrypiq.js

# Make sure the script is executable
chmod +x ~/.cherrypiq/cherrypiq.js

# Reinstall dependencies
echo "Reinstalling dependencies..."
cd ~/.cherrypiq && npm install

# Relink the package
echo "Relinking package..."
cd ~/.cherrypiq && npm unlink && npm link

# Return to original directory
cd "$ORIGINAL_DIR"

echo "Update complete!"
echo "Your local changes have been installed."
echo ""
echo "You can now use the updated cherrypiq from anywhere." 