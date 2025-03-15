#!/bin/bash

# install-cherrypiq.sh
# This script installs the cherrypiq tool

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

# Download the main script
echo "Downloading cherrypiq script..."
curl -o ~/.cherrypiq/cherrypiq.js https://raw.githubusercontent.com/ya1sec/cherrypiq/main/cherrypiq.js || {
    echo "Failed to download script. Using local copy..."
    # If curl fails, copy the locally available script (you'd need to provide the path)
    cat > ~/.cherrypiq/cherrypiq.js << 'EOF'
#!/usr/bin/env node

const blessed = require("blessed");
const fs = require("fs");
const path = require("path");
const { execSync, spawn } = require("child_process");
const { promisify } = require("util");
const readdir = promisify(fs.readdir);
const stat = promisify(fs.stat);
const readFile = promisify(fs.readFile);

// Check if repomix is installed
let repomixInstalled = false;
try {
  execSync("npx repomix --version", { stdio: "ignore" });
  repomixInstalled = true;
} catch (e) {
  console.error(
    "repomix is not installed. Install it with: npm install -g repomix"
  );
  process.exit(1);
}

// Check if ranger is installed
let rangerInstalled = false;
try {
  execSync("which ranger", { stdio: "ignore" });
  rangerInstalled = true;
} catch (e) {
  // Ranger not installed - that's fine
}

// Get gitignore patterns
async function getGitignorePatterns(dir) {
  const patterns = [];
  try {
    const gitignorePath = path.join(dir, ".gitignore");
    if (fs.existsSync(gitignorePath)) {
      const content = await readFile(gitignorePath, "utf8");
      patterns.push(
        ...content
          .split("\n")
          .filter((line) => line && !line.startsWith("#"))
          .map((line) => line.trim())
      );
    }
  } catch (e) {
    // No gitignore or can't read it - that's fine
  }
  return patterns;
}

// Check if a file should be ignored based on gitignore patterns
function shouldIgnore(filePath, patterns) {
  const relativePath = path.relative(process.cwd(), filePath);
  return patterns.some((pattern) => {
    if (pattern.startsWith("!")) {
      return false; // Negation patterns not supported here
    }
    if (pattern.endsWith("/")) {
      // Directory pattern
      return (
        relativePath.startsWith(pattern) || relativePath.includes("/" + pattern)
      );
    }
    // File pattern or glob pattern (simplified)
    return minimatch(relativePath, pattern);
  });
}

// Simplified minimatch function for basic globbing
function minimatch(filePath, pattern) {
  // Convert glob pattern to regex
  const regex = new RegExp(
    "^" +
    pattern
      .replace(/\./g, "\\.") // Escape dots
      .replace(/\*/g, ".*") // Convert * to .*
      .replace(/\?/g, ".") + // Convert ? to .
      "$"
  );
  return regex.test(filePath);
}

// Get directory content
async function getDirectoryContent(
  dir,
  gitignorePatterns,
  selectedFilesArray = []
) {
  const entries = await readdir(dir, { withFileTypes: true });
  const items = await Promise.all(
    entries.map(async (entry) => {
      const fullPath = path.join(dir, entry.name);
      const isDir = entry.isDirectory();
      const ignored = shouldIgnore(fullPath, gitignorePatterns);
      const selected = selectedFilesArray.includes(fullPath);

      return {
        name: entry.name,
        path: fullPath,
        isDir,
        ignored,
        selected,
      };
    })
  );

  // Sort: directories first, then files, alphabetically
  return items.sort((a, b) => {
    if (a.isDir && !b.isDir) return -1;
    if (!a.isDir && b.isDir) return 1;
    return a.name.localeCompare(b.name);
  });
}

// Launch ranger to select files
function launchRanger() {
  return new Promise((resolve, reject) => {
    // Create a temporary file to hold selected paths
    const tempFile = path.join(process.cwd(), ".repomix-selected-files");

    // Clean previous file if exists
    if (fs.existsSync(tempFile)) {
      fs.unlinkSync(tempFile);
    }

    console.log(
      "Launching ranger. Select files with space, then quit with q to return to cherrypiq."
    );

    // Launch ranger with a custom script to handle selection
    const rangerScript = `
      map <space> chain mark_files toggle=True; eval fm.copy(); eval [ for f in fm.copied_files: open(\"${tempFile}\", \"a\").write(f.path + \"\\n\") ]
    `;

    const scriptPath = path.join(process.cwd(), ".repomix-ranger-rc.conf");
    fs.writeFileSync(scriptPath, rangerScript);

    const ranger = spawn("ranger", ["--cmd", `source ${scriptPath}`], {
      stdio: "inherit",
    });

    ranger.on("close", (code) => {
      // Clean up the script
      if (fs.existsSync(scriptPath)) {
        fs.unlinkSync(scriptPath);
      }

      // Read selected files
      if (fs.existsSync(tempFile)) {
        try {
          const selections = fs
            .readFileSync(tempFile, "utf8")
            .split("\n")
            .filter((line) => line.trim());

          fs.unlinkSync(tempFile);
          resolve(selections);
        } catch (e) {
          reject(new Error("Failed to read selected files from ranger"));
        }
      } else {
        resolve([]);
      }
    });
  });
}

// Run repomix with selected files
function runRepomix(selectedFiles) {
  if (selectedFiles.length === 0) {
    console.log("No files selected. Exiting.");
    process.exit(0);
  }

  // Convert absolute paths to relative paths
  const relativePaths = selectedFiles.map((file) =>
    path.relative(process.cwd(), file)
  );

  // Create include pattern for repomix
  const includePattern = relativePaths.join(",");

  console.log(`Running repomix with ${selectedFiles.length} selected files...`);

  try {
    execSync(`npx repomix --include "${includePattern}"`, {
      stdio: "inherit",
    });
    console.log("Repomix completed successfully!");
  } catch (e) {
    console.error("Failed to run repomix:", e.message);
    process.exit(1);
  }
}

// Setup blessed UI
function setupUI() {
  const screen = blessed.screen({
    smartCSR: true,
    title: "cherrypiq",
    fullUnicode: true,
  });

  // Custom file list using a box instead of blessed list
  const list = blessed.box({
    top: 0,
    left: 0,
    width: "100%",
    height: "90%",
    border: {
      type: "line",
    },
    style: {
      border: {
        fg: "white",
      },
    },
    keys: true,
    vi: true,
    mouse: true,
    tags: true,
    scrollable: true,
    alwaysScroll: true,
    scrollbar: {
      ch: " ",
      track: {
        bg: "gray",
      },
      style: {
        inverse: true,
      },
    },
  });

  // Status bar
  const statusBar = blessed.box({
    bottom: 0,
    left: 0,
    width: "100%",
    height: 3,
    content:
      "{bold}cherrypiq{/bold} | {bold}j/k{/bold}: navigate | {bold}space{/bold}: select | {bold}enter{/bold}: open dir | {bold}r{/bold}: run repomix | {bold}R{/bold}: ranger" +
      (rangerInstalled ? "" : " (not installed)") +
      " | {bold}q{/bold}: quit",
    tags: true,
    border: {
      type: "line",
    },
    style: {
      border: {
        fg: "white",
      },
    },
  });

  // Selected count display
  const selectedCount = blessed.box({
    bottom: 0,
    right: 0,
    width: 20,
    height: 3,
    content: "Selected: 0",
    tags: true,
    border: {
      type: "line",
    },
    style: {
      border: {
        fg: "white",
      },
    },
  });

  // Path display
  const pathDisplay = blessed.box({
    top: 0,
    left: 0,
    width: "100%",
    height: 1,
    content: process.cwd(),
    style: {
      bg: "blue",
      fg: "white",
    },
  });

  screen.append(list);
  screen.append(statusBar);
  screen.append(selectedCount);

  return { screen, list, statusBar, selectedCount, pathDisplay };
}

// Main function
async function main() {
  const ui = setupUI();
  const { screen, list, statusBar, selectedCount } = ui;

  let currentDir = process.cwd();
  let currentItems = [];
  let selectedFiles = [];
  let selectedIndex = 0; // Current selection index
  let scrollOffset = 0; // Scroll offset for the list

  // Load initial directory
  const gitignorePatterns = await getGitignorePatterns(currentDir);
  currentItems = await getDirectoryContent(
    currentDir,
    gitignorePatterns,
    selectedFiles
  );

  // Calculate visible height (accounting for borders)
  const getVisibleHeight = () => list.height - 2;

  // Render the file list with custom implementation
  function renderList() {
    const visibleHeight = getVisibleHeight();

    // Ensure scroll offset is valid
    if (selectedIndex < scrollOffset) {
      scrollOffset = selectedIndex;
    } else if (selectedIndex >= scrollOffset + visibleHeight) {
      scrollOffset = selectedIndex - visibleHeight + 1;
    }

    // Create content for the box
    let content = "";

    // Only render visible items
    const visibleItems = currentItems.slice(
      scrollOffset,
      scrollOffset + visibleHeight
    );

    visibleItems.forEach((item, idx) => {
      const isSelected = idx + scrollOffset === selectedIndex;
      let prefix = item.isDir ? "[+] " : "    ";
      prefix = item.selected ? "{green-fg}[✓]{/green-fg} " : prefix;

      let display = item.name;
      if (item.isDir) {
        display = "{bold}" + display + "/{/bold}";
      }
      if (item.ignored) {
        display = "{grey-fg}" + display + "{/grey-fg}";
      }

      // Highlight selected item
      if (isSelected) {
        content += `{blue-bg}{white-fg}${prefix}${display}{/white-fg}{/blue-bg}\n`;
      } else {
        content += `${prefix}${display}\n`;
      }
    });

    // Set content and update UI
    list.setContent(content);
    selectedCount.setContent(`Selected: ${selectedFiles.length}`);
    screen.render();
  }

  // Initial render
  renderList();

  // Custom key handling
  screen.key(["j", "down"], () => {
    if (selectedIndex < currentItems.length - 1) {
      selectedIndex++;
      renderList();
    }
  });

  screen.key(["k", "up"], () => {
    if (selectedIndex > 0) {
      selectedIndex--;
      renderList();
    }
  });

  screen.key(["g", "home"], () => {
    if (currentItems.length > 0) {
      selectedIndex = 0;
      renderList();
    }
  });

  screen.key(["G", "end"], () => {
    if (currentItems.length > 0) {
      selectedIndex = currentItems.length - 1;
      renderList();
    }
  });

  screen.key(["C-d", "pagedown"], () => {
    const pageSize = Math.min(10, currentItems.length);
    selectedIndex = Math.min(selectedIndex + pageSize, currentItems.length - 1);
    renderList();
  });

  screen.key(["C-u", "pageup"], () => {
    const pageSize = Math.min(10, currentItems.length);
    selectedIndex = Math.max(selectedIndex - pageSize, 0);
    renderList();
  });

  // Space: select/deselect file
  screen.key("space", async () => {
    const item = currentItems[selectedIndex];
    if (!item || item.ignored) return;

    if (item.isDir) {
      // Toggle directory selection
      if (selectedFiles.includes(item.path)) {
        // Unmark directory and contents
        const idx = selectedFiles.findIndex((f) => f === item.path);
        if (idx !== -1) selectedFiles.splice(idx, 1);
        await markDirectory(item.path, false);
      } else {
        // Mark directory and contents
        selectedFiles.push(item.path);
        await markDirectory(item.path, true);
      }
    } else {
      // Toggle file selection
      item.selected = !item.selected;
      const idx = selectedFiles.findIndex((f) => f === item.path);

      if (item.selected && idx === -1) {
        selectedFiles.push(item.path);
      } else if (!item.selected && idx !== -1) {
        selectedFiles.splice(idx, 1);
      }
    }

    // Update UI
    renderList();
  });

  // Enter: open directory
  screen.key("enter", async () => {
    const item = currentItems[selectedIndex];
    if (item && item.isDir) {
      currentDir = item.path;
      currentItems = await getDirectoryContent(
        currentDir,
        gitignorePatterns,
        selectedFiles
      );
      selectedIndex = 0; // Reset selection to top
      scrollOffset = 0; // Reset scroll
      renderList();
    }
  });

  // Backspace/h/left: go up one directory
  screen.key(["backspace", "h", "left"], async () => {
    const parentDir = path.dirname(currentDir);
    if (parentDir !== currentDir) {
      currentDir = parentDir;
      currentItems = await getDirectoryContent(
        currentDir,
        gitignorePatterns,
        selectedFiles
      );
      selectedIndex = 0; // Reset selection to top
      scrollOffset = 0; // Reset scroll
      renderList();
    }
  });

  // r: run repomix with selected files
  screen.key("r", () => {
    if (!screen.focused.name === "list") return;
    screen.destroy();
    runRepomix(selectedFiles);
  });

  // R: launch ranger if installed
  screen.key("R", async () => {
    if (!rangerInstalled) {
      statusBar.setContent(
        "{red-bg}Ranger is not installed!{/red-bg} Press any key to continue..."
      );
      screen.render();
      setTimeout(() => {
        statusBar.setContent(
          "{bold}cherrypiq{/bold} | {bold}j/k{/bold}: navigate | {bold}space{/bold}: select | {bold}enter{/bold}: open dir | {bold}r{/bold}: run repomix | {bold}R{/bold}: ranger" +
            (rangerInstalled ? "" : " (not installed)") +
            " | {bold}q{/bold}: quit"
        );
        screen.render();
      }, 3000);
      return;
    }

    screen.destroy();
    console.log("Launching ranger...");

    try {
      const rangerSelectedFiles = await launchRanger();
      if (rangerSelectedFiles.length > 0) {
        selectedFiles = rangerSelectedFiles;
        console.log(`${selectedFiles.length} files selected from ranger.`);

        const rl = require("readline").createInterface({
          input: process.stdin,
          output: process.stdout,
        });

        rl.question("Run repomix with these selections? (y/n) ", (answer) => {
          rl.close();
          if (answer.toLowerCase() === "y") {
            runRepomix(selectedFiles);
          } else {
            main(); // Restart the UI
          }
        });
      } else {
        console.log("No files selected in ranger.");
        main(); // Restart the UI
      }
    } catch (e) {
      console.error("Error using ranger:", e.message);
      main(); // Restart the UI
    }
  });

  // q/Ctrl-c: quit
  screen.key(["q", "C-c"], () => {
    screen.destroy();
    process.exit(0);
  });

  // Mark/unmark all files in directory recursively
  async function markDirectory(dir, mark) {
    const dirItems = await getDirectoryContent(
      dir,
      gitignorePatterns,
      selectedFiles
    );
    for (const dirItem of dirItems) {
      if (dirItem.ignored) continue;

      if (dirItem.isDir) {
        await markDirectory(dirItem.path, mark);
      } else {
        const idx = selectedFiles.findIndex((f) => f === dirItem.path);
        if (mark && idx === -1) {
          selectedFiles.push(dirItem.path);
        } else if (!mark && idx !== -1) {
          selectedFiles.splice(idx, 1);
        }
      }
    }
  }

  // Focus handling
  list.focus();
  screen.render();
}

// Start the application
main().catch((err) => {
  console.error("Error:", err);
  process.exit(1);
});
EOF
}

# Make the script executable
chmod +x ~/.cherrypiq/cherrypiq.js

# Create global symlink
echo "Creating global symlink..."
cd ~/.cherrypiq && npm link

# # Download ranger integration script (if ranger is installed)
# if command -v ranger &> /dev/null; then
#     echo "Ranger detected, installing ranger integration..."
#     curl -o ~/.cherrypiq/ranger-repomix-integration.sh https://raw.githubusercontent.com/ya1sec/cherrypiq/main/ranger-repomix-integration.sh || {
#         echo "Failed to download ranger integration script. Using local copy..."
#         # If curl fails, copy the locally available script
#         cat > ~/.cherrypiq/ranger-repomix-integration.sh << 'EOF'
# #!/bin/bash

# # ranger-repomix-integration.sh
# # This script helps integrate ranger file manager with repomix

# # Check if ranger is installed
# if ! command -v ranger &> /dev/null; then
#     echo "Ranger is not installed. Install it first."
#     exit 1
# fi

# # Check if repomix is installed
# if ! command -v repomix &> /dev/null && ! npm list -g repomix &> /dev/null; then
#     echo "Repomix is not installed. Install it with 'npm install -g repomix' first."
#     exit 1
# fi

# # Create a temporary rc.conf for ranger
# TEMP_RC_CONF="/tmp/ranger_repomix_rc.conf"
# SELECTED_FILES="/tmp/repomix_selected_files.txt"

# # Clean up any existing file
# rm -f "$SELECTED_FILES"
# touch "$SELECTED_FILES"

# # Create ranger configuration for file selection
# cat > "$TEMP_RC_CONF" << 'EOF'
# # Repomix integration for ranger

# # Mark files with space and save to repomix selection file
# map <space> chain mark_files toggle=True; shell echo %p >> /tmp/repomix_selected_files.txt

# # Custom command to run repomix with selected files
# map ,r shell cat /tmp/repomix_selected_files.txt | sort | uniq | tr '\n' ',' | xargs -I{} repomix --include "{}"

# # Show help information
# map ,h shell echo "Repomix Integration Help:\n\n<space> - Mark/unmark file for inclusion\n,r - Run repomix with selected files\n,h - Show this help\n,c - Clear selection" | less

# # Clear selection
# map ,c shell rm -f /tmp/repomix_selected_files.txt && touch /tmp/repomix_selected_files.txt && echo "Selection cleared"
# EOF

# # Launch ranger with the custom configuration
# echo "=== Ranger-Repomix Integration ==="
# echo "Use <space> to select files for repomix"
# echo "Press ,r to run repomix with selected files"
# echo "Press ,h for help"
# echo "Press ,c to clear selection"
# echo "===============================>"

# ranger --cmd="source $TEMP_RC_CONF"

# # Clean up
# echo "Cleaning up temporary files..."
# rm -f "$TEMP_RC_CONF"

# # Check if any files were selected and not processed
# if [ -s "$SELECTED_FILES" ]; then
#     echo "You still have selected files that were not processed."
#     echo "Would you like to run repomix with these files? (y/n)"
#     read -r answer
    
#     if [[ "$answer" =~ ^[Yy]$ ]]; then
#         # Get unique files and convert to comma-separated list
#         INCLUDE_LIST=$(cat "$SELECTED_FILES" | sort | uniq | tr '\n' ',')
#         # Remove trailing comma
#         INCLUDE_LIST=${INCLUDE_LIST%,}
        
#         echo "Running: repomix --include \"$INCLUDE_LIST\""
#         repomix --include "$INCLUDE_LIST"
#     fi
# fi

# # Final cleanup
# rm -f "$SELECTED_FILES"
# echo "Done."
# EOF
#     }
    
#     chmod +x ~/.cherrypiq/ranger-repomix-integration.sh
#     ln -sf ~/.cherrypiq/ranger-repomix-integration.sh /usr/local/bin/ranger-repomix || {
#         echo "Failed to create global symlink for ranger integration. You may need sudo:"
#         echo "sudo ln -sf ~/.cherrypiq/ranger-repomix-integration.sh /usr/local/bin/ranger-repomix"
#     }
# fi

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