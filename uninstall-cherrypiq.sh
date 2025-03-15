#!/bin/bash

# uninstall-cherrypiq.sh
# This script uninstalls the cherrypiq tool

echo "Uninstalling cherrypiq..."

# Remove global npm link
echo "Removing global npm link..."
npm unlink -g cherrypiq 2>/dev/null || npm uninstall -g cherrypiq 2>/dev/null

# Remove ranger integration if it exists
if [ -f /usr/local/bin/ranger-repomix ]; then
    echo "Removing ranger integration..."
    sudo rm -f /usr/local/bin/ranger-repomix 2>/dev/null || {
        echo "Failed to remove ranger integration symlink. You may need to manually remove it:"
        echo "sudo rm -f /usr/local/bin/ranger-repomix"
    }
fi

# Remove cherrypiq directory
echo "Removing cherrypiq files..."
if [ -d ~/.cherrypiq ]; then
    rm -rf ~/.cherrypiq
    echo "Removed ~/.cherrypiq directory"
else
    echo "No cherrypiq directory found at ~/.cherrypiq"
fi

# Check if global packages were installed by cherrypiq
echo "Checking for global packages installed by cherrypiq..."
if npm list -g repomix &>/dev/null; then
    echo "Found global package 'repomix' that was installed by cherrypiq."
    read -p "Do you want to uninstall repomix as well? (y/n): " uninstall_repomix
    if [[ "$uninstall_repomix" =~ ^[Yy]$ ]]; then
        npm uninstall -g repomix
        echo "Uninstalled repomix"
    else
        echo "Keeping repomix installed"
    fi
fi

if npm list -g blessed &>/dev/null; then
    echo "Found global package 'blessed' that was installed by cherrypiq."
    read -p "Do you want to uninstall blessed as well? (y/n): " uninstall_blessed
    if [[ "$uninstall_blessed" =~ ^[Yy]$ ]]; then
        npm uninstall -g blessed
        echo "Uninstalled blessed"
    else
        echo "Keeping blessed installed"
    fi
fi

# Clean up any temporary files that might have been created
echo "Cleaning up temporary files..."
rm -f /tmp/ranger_repomix_rc.conf 2>/dev/null
rm -f /tmp/repomix_selected_files.txt 2>/dev/null
rm -f .repomix-selected-files 2>/dev/null
rm -f .repomix-ranger-rc.conf 2>/dev/null

echo "Uninstallation complete!"
echo "cherrypiq has been removed from your system." 