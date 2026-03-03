#!/bin/bash
# ══════════════════════════════════════════════════════════════════
# Sandbox Guard Uninstaller
# ══════════════════════════════════════════════════════════════════
set -e

INSTALL_DIR="$HOME/.claude/guard"
SETTINGS_FILE="$HOME/.claude/settings.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $1"; }
info() { echo -e "  ${CYAN}[..]${NC} $1"; }

echo ""
echo -e "${CYAN}  Sandbox Guard — Uninstaller${NC}"
echo ""

# ── Remove hook from settings.json ──────────────────────────────
if [ -f "$SETTINGS_FILE" ]; then
  PYTHON_CMD=""
  for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
      PYTHON_CMD="$cmd"
      break
    fi
  done

  if [ -n "$PYTHON_CMD" ]; then
    PYTHON_REMOVE='
import json, sys

settings_path = sys.argv[1]

with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
pre_hooks = hooks.get("PreToolUse", [])
pre_hooks = [h for h in pre_hooks if "sandbox-guard" not in json.dumps(h)]

if pre_hooks:
    hooks["PreToolUse"] = pre_hooks
else:
    hooks.pop("PreToolUse", None)

if not hooks:
    settings.pop("hooks", None)

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2)

print("OK")
'
    RESULT=$($PYTHON_CMD -c "$PYTHON_REMOVE" "$SETTINGS_FILE" 2>&1)
    if [ "$RESULT" = "OK" ]; then
      ok "Hook removed from settings.json"
    else
      warn "Could not remove hook: $RESULT"
      info "Manually remove the sandbox-guard entry from ~/.claude/settings.json"
    fi
  else
    warn "Python not found — cannot auto-remove hook from settings.json"
    info "Manually remove the sandbox-guard entry from ~/.claude/settings.json"
  fi
else
  info "No settings.json found"
fi

# ── Remove guard directory ──────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
  echo ""
  read -p "  Delete $INSTALL_DIR and all logs? [y/N]: " CONFIRM
  if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
    rm -rf "$INSTALL_DIR"
    ok "Guard directory removed"
  else
    info "Kept $INSTALL_DIR (you can delete it manually)"
  fi
else
  info "Guard directory not found at $INSTALL_DIR"
fi

echo ""
echo -e "${GREEN}  Uninstall complete.${NC}"
echo "  Sandbox Guard has been removed. Start a new Claude Code"
echo "  session for changes to take effect."
echo ""
