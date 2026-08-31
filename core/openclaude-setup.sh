#!/bin/bash
# Android Subsystem for Linux (ASL): Automated OpenClaude & AI-Agentic Suite Installer
# Automatically installs OpenClaude CLI in Termux with memory, infinite turns, and keyless web search pre-configured.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

OPENCLAUDE_CONF_DIR="$HOME/.openclaude"
SETTINGS_FILE="$OPENCLAUDE_CONF_DIR/settings.json"

echo -e "\033[0;36m[*] Configuring OpenClaude AI Agentic Environment on Termux...\033[0m"

# 1. Install Node.js if missing
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo -e "\033[0;32m[*] Installing Node.js & NPM dependencies...\033[0m"
    pkg install -y nodejs python 2>/dev/null || apt-get install -y nodejs python3 2>/dev/null || true
fi

# 2. Install / Update OpenClaude CLI globally
if ! command -v openclaude >/dev/null 2>&1; then
    echo -e "\033[0;32m[*] Installing OpenClaude CLI (@gitlawb/openclaude)...\033[0m"
    npm install -g @gitlawb/openclaude --force 2>/dev/null || true
fi

# 3. Configure ~/.openclaude/settings.json with Infinite Turns, Memory & Full Permissions
mkdir -p "$OPENCLAUDE_CONF_DIR"

if [ -f "$SETTINGS_FILE" ]; then
    echo -e "\033[0;32m[*] Updating OpenClaude settings at $SETTINGS_FILE...\033[0m"
else
    echo -e "\033[0;32m[*] Provisioning fresh OpenClaude configuration at $SETTINGS_FILE...\033[0m"
fi

python3 -c '
import json, os

config_path = os.path.expanduser("~/.openclaude/settings.json")
data = {}
if os.path.exists(config_path):
    try:
        with open(config_path, "r") as f:
            data = json.load(f)
    except Exception:
        data = {}

# Ensure env block
if "env" not in data or not isinstance(data["env"], dict):
    data["env"] = {}

data["env"]["OPENCLAUDE_MAX_TURNS"] = "0"
data["env"]["ENABLE_FREE_WEB_SEARCH"] = "1"

# Permissions & auto-memory
if "permissions" not in data or not isinstance(data["permissions"], dict):
    data["permissions"] = {}

data["permissions"]["defaultMode"] = "fullAccess"
data["skipFullAccessModePermissionPrompt"] = True
data["autoMemoryEnabled"] = True

if "memory" not in data or not isinstance(data["memory"], dict):
    data["memory"] = {}

data["memory"]["autoWrite"] = True
data["memory"]["requireApprovalBeforeWrite"] = False

with open(config_path, "w") as f:
    json.dump(data, f, indent=2)
' 2>/dev/null || true

# 4. Ensure free web search engine executable perm
if [ -f "$SCRIPT_DIR/tools/free-web-search.py" ]; then
    chmod +x "$SCRIPT_DIR/tools/free-web-search.py" 2>/dev/null || true
fi

echo -e "\033[0;32m[✓] OpenClaude AI environment configured: Memory ENABLED, Infinite Turns ENABLED, Web Search ENABLED.\033[0m"
