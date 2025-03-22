#!/usr/bin/env node

const blessed = require("blessed");
const fs = require("fs");
const path = require("path");
const { execSync, spawn } = require("child_process");
const { promisify } = require("util");
const readdir = promisify(fs.readdir);
const stat = promisify(fs.stat);
const readFile = promisify(fs.readFile);

// Try to load gpt-tokenizer, fall back to basic counting if not available
let gptTokenizer = null;
try {
  gptTokenizer = require("gpt-tokenizer");
} catch (e) {
  // gpt-tokenizer not available - will use basic counting
}

// Handle update command
if (process.argv[2] === "update") {
  const currentDir = process.cwd();
  const cherrypiqJs = path.join(currentDir, "cherrypiq.js");
  const cherrypiqInstallDir = path.join(process.env.HOME, ".cherrypiq");

  // Check if cherrypiq.js exists in current directory
  if (!fs.existsSync(cherrypiqJs)) {
    console.error("Error: cherrypiq.js not found in current directory.");
    console.error(
      "Please run this command from the directory containing your modified cherrypiq.js"
    );
    process.exit(1);
  }

  // Check if ~/.cherrypiq exists
  if (!fs.existsSync(cherrypiqInstallDir)) {
    console.error("Error: cherrypiq installation directory not found.");
    console.error("Please install cherrypiq first using install-cherrypiq.sh");
    process.exit(1);
  }

  try {
    // Copy the local cherrypiq.js to the installation directory
    console.log("Copying local cherrypiq.js to installation directory...");
    fs.copyFileSync(
      cherrypiqJs,
      path.join(cherrypiqInstallDir, "cherrypiq.js")
    );

    // Make sure the script is executable
    fs.chmodSync(path.join(cherrypiqInstallDir, "cherrypiq.js"), "755");

    // Add gpt-tokenizer to package.json
    console.log("Adding gpt-tokenizer to dependencies...");
    const packageJsonPath = path.join(cherrypiqInstallDir, "package.json");
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
    packageJson.dependencies = packageJson.dependencies || {};
    packageJson.dependencies["gpt-tokenizer"] = "^2.4.0";
    fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2));

    // Install dependencies
    console.log("Installing dependencies...");
    execSync("npm install", { cwd: cherrypiqInstallDir, stdio: "inherit" });

    // Relink the package
    console.log("Relinking package...");
    try {
      // Try to unlink first, but don't error if it fails
      execSync("npm unlink -g cherrypiq", {
        cwd: cherrypiqInstallDir,
        stdio: "inherit",
      });
    } catch (e) {
      // Ignore unlink errors - package might not be linked
    }
    // Now link the package
    execSync("npm link", { cwd: cherrypiqInstallDir, stdio: "inherit" });

    console.log("\nUpdate complete!");
    console.log("Your local changes have been installed.");
    console.log("\nYou can now use the updated cherrypiq from anywhere.");
    process.exit(0);
  } catch (error) {
    console.error("Error during update:", error.message);
    process.exit(1);
  }
}

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

// Check if bat is installed
let batInstalled = false;
try {
  execSync("which bat", { stdio: "ignore" });
  batInstalled = true;
} catch (e) {
  try {
    execSync("which batcat", { stdio: "ignore" }); // For Ubuntu/Debian
    batInstalled = true;
  } catch (e) {
    // bat not installed - that's fine
  }
}

// Get bat command (handles both 'bat' and 'batcat' names)
function getBatCommand() {
  try {
    execSync("which bat", { stdio: "ignore" });
    return "bat";
  } catch (e) {
    return "batcat"; // For Ubuntu/Debian
  }
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

// Run repomix and copy output to clipboard
async function runRepomixToClipboard(selectedFiles) {
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

  try {
    execSync(`npx repomix --include "${includePattern}" --copy`, {
      stdio: "inherit",
    });
    return true;
  } catch (e) {
    console.error("Failed to run repomix:", e.message);
    return false;
  }
}

// Create prompt input box
function createPromptInput(screen) {
  const promptBox = blessed.box({
    top: "center",
    left: "center",
    width: "80%",
    height: 7,
    hidden: true, // Hide by default
    content: "{bold}Enter Prompt for Repomix{/bold}",
    tags: true,
    border: {
      type: "line",
    },
    style: {
      border: {
        fg: "white",
      },
      focus: {
        border: {
          fg: "green",
        },
      },
    },
  });

  const promptInput = blessed.textbox({
    parent: promptBox,
    top: 2,
    left: 1,
    right: 1,
    height: 3,
    inputOnFocus: true,
    border: {
      type: "line",
    },
    style: {
      border: {
        fg: "white",
      },
      focus: {
        border: {
          fg: "green",
        },
      },
    },
  });

  // Add a small help text
  const helpText = blessed.box({
    parent: promptBox,
    bottom: 0,
    left: 1,
    content: "Enter: Submit | Esc: Cancel",
    style: {
      fg: "gray",
    },
  });

  return { promptBox, promptInput };
}

// Run repomix with custom prompt
async function runRepomixWithPrompt(selectedFiles, prompt) {
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

  try {
    const output = execSync(
      `npx repomix --include "${includePattern}" --prompt "${prompt}"`,
      {
        encoding: "utf8",
      }
    );
    return output;
  } catch (e) {
    console.error("Failed to run repomix:", e.message);
    return null;
  }
}

// Setup blessed UI
function setupUI() {
  const screen = blessed.screen({
    smartCSR: true,
    title: "cherrypiq",
    fullUnicode: true,
  });

  // Left column for file navigation
  const leftColumn = blessed.box({
    top: 0,
    left: 0,
    width: "60%",
    height: "100%",
    border: {
      type: "line",
    },
    style: {
      border: {
        fg: "white",
      },
    },
  });

  // File list
  const list = blessed.box({
    parent: leftColumn,
    top: 1, // Leave space for path display
    left: 0,
    width: "100%-2", // Account for borders
    height: "100%-4", // Account for borders and path display
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

  // Right column
  const rightColumn = blessed.box({
    top: 0,
    right: 0,
    width: "40%",
    height: "100%",
    border: {
      type: "line",
    },
    style: {
      border: {
        fg: "white",
      },
    },
  });

  // Token count display in top half of right column
  const tokenCount = blessed.box({
    parent: rightColumn,
    top: 1,
    left: 1,
    width: "100%-2",
    height: "30%",
    content: "Token Count: 0",
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

  // Command help in bottom half of right column
  const commandHelp = blessed.box({
    parent: rightColumn,
    top: "30%",
    left: 1,
    width: "100%-2",
    height: "70%",
    content:
      "{bold}Commands{/bold}\n\n" +
      "Navigation:\n" +
      "  j/↓: Move down\n" +
      "  k/↑: Move up\n" +
      "  g: Go to top\n" +
      "  G: Go to bottom\n" +
      "  h/←: Go up dir\n" +
      "  l/→/enter: Open dir\n\n" +
      "Selection:\n" +
      "  space: Select file/dir\n" +
      "  p: Preview file\n" +
      "  esc: Close preview\n\n" +
      "Actions:\n" +
      "  r: Run repomix\n" +
      "  c: Copy to clipboard\n" +
      "  i: Input prompt\n" +
      "  R: Launch ranger\n" +
      "  ?: Toggle help\n" +
      "  q: Quit",
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

  // Path display at top of left column
  const pathDisplay = blessed.box({
    parent: leftColumn,
    top: 0,
    left: 0,
    width: "100%-2",
    height: 1,
    content: process.cwd(),
    style: {
      bg: "blue",
      fg: "white",
    },
  });

  // Selected count display at bottom of left column
  const selectedCount = blessed.box({
    parent: leftColumn,
    bottom: 0,
    left: 0,
    width: "100%-2",
    height: 1,
    content: "Selected: 0",
    tags: true,
    style: {
      bg: "blue",
      fg: "white",
    },
  });

  // Preview popup for bat
  const previewBox = blessed.box({
    top: "center",
    left: "center",
    width: "80%",
    height: "80%",
    hidden: true,
    border: {
      type: "line",
    },
    style: {
      border: {
        fg: "white",
      },
    },
    tags: true,
    scrollable: true,
    alwaysScroll: true,
    keys: true,
    vi: true,
    mouse: true,
  });

  // Prompt input box
  const { promptBox, promptInput } = createPromptInput(screen);

  screen.append(leftColumn);
  screen.append(rightColumn);
  screen.append(previewBox);
  screen.append(promptBox);

  return {
    screen,
    list,
    pathDisplay,
    selectedCount,
    tokenCount,
    commandHelp,
    previewBox,
    promptBox,
    promptInput,
  };
}

// Main function
async function main() {
  const ui = setupUI();
  const {
    screen,
    list,
    pathDisplay,
    selectedCount,
    tokenCount,
    commandHelp,
    previewBox,
    promptBox,
    promptInput,
  } = ui;

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
      prefix = item.selected ? "{red-fg}[✓]{/red-fg} " : prefix;

      let display = item.name;
      if (item.isDir) {
        display = "{bold}" + display + "/{/bold}";
      }
      if (item.ignored) {
        display = "{grey-fg}" + display + "{/grey-fg}";
      }
      if (item.selected) {
        display = "{yellow-fg}" + display + "{/yellow-fg}";
      }

      // Highlight selected item
      if (isSelected) {
        content += `{blue-bg}${prefix}${display}{/blue-bg}\n`;
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

    // Update UI and token count
    await updateTokenCount(selectedFiles, tokenCount);
    renderList();
  });

  // Enter: open directory
  screen.key(["enter", "l", "o", "right"], async () => {
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
      commandHelp.setContent(
        "{red-bg}Ranger is not installed!{/red-bg} Press any key to continue..."
      );
      screen.render();
      setTimeout(() => {
        commandHelp.setContent(
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

  // Calculate token count for a file
  async function calculateTokenCount(filePath) {
    try {
      const content = await readFile(filePath, "utf8");

      // Count non-empty lines
      const lines = content.split("\n").filter((line) => line.trim());

      // Count characters excluding whitespace
      const chars = content.replace(/\s+/g, "").length;

      let tokenCount;
      if (gptTokenizer) {
        // Use GPT tokenizer if available
        tokenCount = gptTokenizer.countTokens(content);
      } else {
        // Basic token estimation if gpt-tokenizer not available
        const noComments = content
          .replace(/\/\*[\s\S]*?\*\//g, "") // Remove multi-line comments
          .replace(/\/\/.*/g, ""); // Remove single-line comments

        const tokens = noComments
          .replace(/([{}()\[\].,;=+\-*/<>!&|%^~?:])/g, " $1 ")
          .replace(/'[^']*'|"[^"]*"|`[^`]*`/g, (match) =>
            match.replace(/\s/g, "")
          )
          .replace(/\s+/g, " ")
          .trim()
          .split(" ")
          .filter((token) => token.length > 0);

        tokenCount = tokens.length;
      }

      return {
        lines: lines.length,
        tokens: tokenCount,
        chars: chars,
      };
    } catch (error) {
      return { lines: 0, tokens: 0, chars: 0 };
    }
  }

  // Update token count display
  async function updateTokenCount(selectedFiles, tokenCount) {
    let totalLines = 0;
    let totalTokens = 0;
    let totalChars = 0;

    for (const file of selectedFiles) {
      const stats = await calculateTokenCount(file);
      totalLines += stats.lines;
      totalTokens += stats.tokens;
      totalChars += stats.chars;
    }

    const tokenCounterType = gptTokenizer
      ? "Using OpenAI's cl100k_base tokenizer\n(same as GPT-3.5/4)"
      : "Using basic token estimation";

    tokenCount.setContent(
      "{bold}Code Statistics{/bold}\n\n" +
        `Selected Files: ${selectedFiles.length}\n` +
        `Lines of Code: ${totalLines}\n` +
        `${gptTokenizer ? "GPT" : "Estimated"} Tokens: ${totalTokens}\n` +
        `Characters: ${totalChars}\n\n` +
        `Note: ${tokenCounterType}`
    );
  }

  // Preview file using bat
  async function previewFile(filePath, previewBox) {
    if (!batInstalled) {
      previewBox.setContent(
        "{red-fg}bat is not installed. Install it for file preview functionality.{/red-fg}"
      );
      previewBox.show();
      previewBox.focus();
      return;
    }

    try {
      const batCmd = getBatCommand();
      const output = execSync(
        `${batCmd} --paging=always --color=always --style=numbers,changes "${filePath}"`,
        {
          encoding: "utf8",
          maxBuffer: 10 * 1024 * 1024, // 10MB buffer
        }
      );

      previewBox.setContent(output);
      previewBox.show();
      previewBox.focus();

      // Prevent key events from bubbling up when preview is focused
      const preventBubbling = (ch, key) => {
        if (
          previewBox.visible &&
          [
            "j",
            "k",
            "g",
            "G",
            "up",
            "down",
            "pageup",
            "pagedown",
            "home",
            "end",
          ].includes(key.name)
        ) {
          return false;
        }
      };

      screen.on("keypress", preventBubbling);

      // Remove the event listener when preview is closed
      previewBox.once("hide", () => {
        screen.removeListener("keypress", preventBubbling);
        list.focus();
      });
    } catch (error) {
      previewBox.setContent(
        `{red-fg}Error previewing file: ${error.message}{/red-fg}`
      );
      previewBox.show();
      previewBox.focus();
    }
  }

  // Add preview key binding in main()
  screen.key("p", async () => {
    const item = currentItems[selectedIndex];
    if (!item || item.isDir) return;

    await previewFile(item.path, previewBox);
    screen.render();
  });

  // Add escape key to close preview
  screen.key("escape", () => {
    if (previewBox.visible) {
      previewBox.hide();
      screen.render();
    }
  });

  // Add key bindings for clipboard and prompt features
  screen.key("c", async () => {
    if (!screen.focused.name === "list") return;
    const success = await runRepomixToClipboard(selectedFiles);
    if (success) {
      screen.destroy();
      console.log("Repomix output copied to clipboard!");
    }
  });

  screen.key("i", () => {
    if (!screen.focused.name === "list") return;
    promptBox.show();
    promptInput.clearValue();
    promptInput.focus();
    screen.render();
  });

  promptInput.key(["enter"], async () => {
    const prompt = promptInput.getValue().trim();
    if (!prompt) {
      promptBox.hide();
      list.focus();
      screen.render();
      return;
    }

    promptBox.hide();
    screen.render();

    const output = await runRepomixWithPrompt(selectedFiles, prompt);
    if (output) {
      screen.destroy();
      console.log(output);
    }
  });

  promptInput.key(["escape"], () => {
    promptInput.clearValue();
    promptBox.hide();
    list.focus();
    screen.render();
  });

  // Focus handling
  list.focus();
  screen.render();
}

// Start the application
main().catch((err) => {
  console.error("Error:", err);
  process.exit(1);
});
