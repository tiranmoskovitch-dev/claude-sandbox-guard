#!/bin/bash
# ══════════════════════════════════════════════════════════════════
# Claude Code Sandbox Guard v3 — Contain, Teach, Protect
# ══════════════════════════════════════════════════════════════════
# Philosophy: ALLOW the AI to work. CONTAIN risky ops to safe zones.
# When blocking, TEACH the AI the safe alternative so it can retry.
# Only HARD BLOCK things that are truly irreversible and system-level.
#
# Exit 0 = allow | Exit 2 = block (stderr message guides the AI)
# ══════════════════════════════════════════════════════════════════

# ── Self-locate ─────────────────────────────────────────────────
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR="$SCRIPT_DIR/logs"
TMP_DIR="$SCRIPT_DIR/tmp"
mkdir -p "$LOG_DIR" "$TMP_DIR"

# ── Config ──────────────────────────────────────────────────────
SAFE_ZONE="/e/"
if [ -f "$SCRIPT_DIR/config.sh" ]; then
  source "$SCRIPT_DIR/config.sh"
fi

# ── Detect OS ───────────────────────────────────────────────────
OS_TYPE="unknown"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS_TYPE="windows" ;;
  Darwin*)               OS_TYPE="macos"   ;;
  Linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      OS_TYPE="wsl"
    else
      OS_TYPE="linux"
    fi
    ;;
esac

# ── Parse input ─────────────────────────────────────────────────
INPUT=$(cat)
TOOL=$(echo "$INPUT" | grep -o '"tool_name":"[^"]*"' | sed 's/"tool_name":"//;s/"//')
COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"//')

if [ "$TOOL" != "Bash" ] || [ -z "$COMMAND" ]; then
  exit 0
fi

CMD_LOWER=$(echo "$COMMAND" | tr '[:upper:]' '[:lower:]')

# ── LOGGING ───────────────────────────────────────────────────────

log_ok() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] OK | $COMMAND" >> "$LOG_DIR/commands.log"
}

log_block() {
  local reason="$1"
  local alternative="$2"
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] BLOCKED | $reason | $COMMAND | ALT: $alternative" >> "$LOG_DIR/blocked.log"
}

log_contained() {
  local reason="$1"
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] CONTAINED | $reason | $COMMAND" >> "$LOG_DIR/commands.log"
}

block() {
  local reason="$1"
  local alternative="$2"
  echo "BLOCKED by sandbox-guard: $reason" >&2
  if [ -n "$alternative" ]; then
    echo "SAFE ALTERNATIVE: $alternative" >&2
  fi
  log_block "$reason" "$alternative"
  exit 2
}

# ── CONTAINMENT CHECKS ───────────────────────────────────────────
# Normalize safe zone for matching (lowercase, ensure trailing slash)
SAFE_ZONE_LOWER=$(echo "$SAFE_ZONE" | tr '[:upper:]' '[:lower:]' | sed 's:/*$:/:')
SAFE_ZONE_NOSLASH=$(echo "$SAFE_ZONE_LOWER" | sed 's:/$::')

targets_safe_zone() {
  [[ "$CMD_LOWER" == *"$SAFE_ZONE_NOSLASH"* ]] && return 0
  return 1
}

targets_localhost() {
  echo "$CMD_LOWER" | grep -qiE "(localhost|127\.0\.0\.1|0\.0\.0\.0)" && return 0
  return 1
}

targets_system() {
  case "$OS_TYPE" in
    windows|wsl)
      echo "$CMD_LOWER" | grep -qiE "(/c/windows|/c/program files|c:\\\\windows|c:\\\\program)" && return 0
      ;;
    macos)
      echo "$CMD_LOWER" | grep -qiE "(/system|/library|/usr/local/cellar)" && return 0
      ;;
    linux)
      echo "$CMD_LOWER" | grep -qiE "(/usr/bin|/usr/sbin|/etc/|/boot/|/var/lib/dpkg|/var/lib/apt)" && return 0
      ;;
  esac
  return 1
}

# ══════════════════════════════════════════════════════════════════
# RULE 1: PIPE-TO-EXECUTE
# ══════════════════════════════════════════════════════════════════
# Allow: localhost pipes (dev server testing)
# Allow: pipes to formatting tools (-m json.tool, jq, head, grep)
# Block: remote URL piped to interpreters — but teach the safe way

if echo "$CMD_LOWER" | grep -qiE "(curl|wget).*\|"; then
  if targets_localhost; then
    log_contained "Pipe from localhost — safe, contained"
    log_ok
    exit 0
  fi

  if echo "$CMD_LOWER" | grep -qiE "\| *(head|tail|grep|wc|sort|uniq|tee|less|more|cat|jq|python[0-9.]* *-m *json)" ; then
    log_ok
    exit 0
  fi

  if echo "$CMD_LOWER" | grep -qiE "\| *(bash|sh |sh$)"; then
    block "Remote content piped to shell" \
      "Download first, then run separately: curl -o ${TMP_DIR}/script.sh <URL> && cat ${TMP_DIR}/script.sh && bash ${TMP_DIR}/script.sh"
  fi
  if echo "$CMD_LOWER" | grep -qiE "\| *python[0-9.]* *-c"; then
    block "Remote content piped to python -c" \
      "Download first: curl -o ${TMP_DIR}/data.txt <URL> then python -c '...' < ${TMP_DIR}/data.txt"
  fi
  if echo "$CMD_LOWER" | grep -qiE "\| *python[0-9.]* *$"; then
    block "Remote content piped to python stdin" \
      "Download the script first: curl -o ${TMP_DIR}/script.py <URL> && cat ${TMP_DIR}/script.py && python ${TMP_DIR}/script.py"
  fi
  if echo "$CMD_LOWER" | grep -qiE "\| *node"; then
    block "Remote content piped to node" \
      "Download first: curl -o ${TMP_DIR}/script.js <URL> && cat ${TMP_DIR}/script.js && node ${TMP_DIR}/script.js"
  fi
  if echo "$CMD_LOWER" | grep -qiE "\| *powershell|\| *pwsh|\| *iex"; then
    block "Remote content piped to PowerShell" \
      "Download first: curl -o ${TMP_DIR}/script.ps1 <URL> — then review it before running"
  fi
fi

# Download-then-execute chained pattern
if echo "$CMD_LOWER" | grep -qiE "curl.*>.*\.(sh|bat|ps1|cmd|vbs).*&&"; then
  block "Download-then-execute chain" \
    "Split into two steps: 1) curl -o ${TMP_DIR}/file <URL> 2) Review the file 3) Run it"
fi

# PowerShell IEX patterns
echo "$CMD_LOWER" | grep -qiE "invoke-webrequest.*\|.*invoke-expression" && block "PowerShell IWR|IEX" "Download with Invoke-WebRequest -OutFile, review, then run"
echo "$CMD_LOWER" | grep -qiE "(iwr|irm).*\|.*iex" && block "PowerShell shorthand IEX" "Download to file first, review, then execute"

# ══════════════════════════════════════════════════════════════════
# RULE 2: ENCODED/OBFUSCATED EXECUTION (always block, no safe alt)
# ══════════════════════════════════════════════════════════════════

echo "$CMD_LOWER" | grep -qiE "base64.*(--decode|-d).*\|.*(bash|sh|python|node)" && block "Base64 decoded content piped to interpreter" "Write the actual command in plain text instead of encoding it"
echo "$CMD_LOWER" | grep -qiE "powershell.*-enc" && block "PowerShell encoded command" "Write the PowerShell command in plain text"
echo "$CMD_LOWER" | grep -qiE "powershell.*-e " && block "PowerShell -e flag" "Write the PowerShell command in plain text"

# ══════════════════════════════════════════════════════════════════
# RULE 3: SYSTEM DESTRUCTION (always hard block)
# ══════════════════════════════════════════════════════════════════

case "$OS_TYPE" in
  windows|wsl)
    echo "$CMD_LOWER" | grep -qiE "format [a-z]:" && block "Drive formatting" "This cannot be done safely through automation"
    echo "$CMD_LOWER" | grep -qiE "diskpart" && block "Disk partitioning" "Use Disk Management GUI instead"
    echo "$CMD_LOWER" | grep -qiE "bcdedit" && block "Boot config modification" "This cannot be done safely through automation"
    echo "$CMD_LOWER" | grep -qiE "cipher /w:" && block "Cipher wipe" "This cannot be undone"
    ;;
  macos)
    echo "$CMD_LOWER" | grep -qiE "diskutil (erase|partition)" && block "Disk modification" "Use Disk Utility GUI instead"
    echo "$CMD_LOWER" | grep -qiE "nvram" && block "NVRAM modification" "This cannot be done safely through automation"
    ;;
  linux)
    echo "$CMD_LOWER" | grep -qiE "mkfs\." && block "Filesystem formatting" "This cannot be done safely through automation"
    echo "$CMD_LOWER" | grep -qiE "fdisk|parted|gdisk" && block "Disk partitioning" "Use a disk management GUI instead"
    echo "$CMD_LOWER" | grep -qiE "dd if=.*/dev/" && block "Raw disk write" "This cannot be done safely through automation"
    ;;
esac

# ══════════════════════════════════════════════════════════════════
# RULE 4: RECURSIVE DELETION
# ══════════════════════════════════════════════════════════════════
# Safe zone = ALLOW (it's the dev zone, git can restore)
# System drives = HARD BLOCK

if echo "$CMD_LOWER" | grep -qiE "rm -rf "; then
  # ALLOW in safe zone — contained and reversible via git
  if targets_safe_zone && ! echo "$CMD_LOWER" | grep -qiE "rm -rf ${SAFE_ZONE_NOSLASH}$"; then
    log_contained "Recursive delete in safe zone — allowed (reversible via git)"
    log_ok
    exit 0
  fi
  # BLOCK on dangerous paths
  echo "$CMD_LOWER" | grep -qiE "rm -rf /*$" && block "Root filesystem recursive delete" "Specify the exact directory in your safe zone instead"
  echo "$CMD_LOWER" | grep -qiE "rm -rf ~" && block "Home directory recursive delete" "Delete specific subdirectories instead, or work in your safe zone"
  echo "$CMD_LOWER" | grep -qiE "rm -rf /mnt" && block "Mount point recursive delete" "Specify the exact directory to delete"

  case "$OS_TYPE" in
    windows|wsl)
      echo "$CMD_LOWER" | grep -qiE "rm -rf /c" && block "C: drive recursive delete" "Only delete in your safe zone ($SAFE_ZONE). Use: rm -rf ${SAFE_ZONE}<project>/<dir>"
      echo "$CMD_LOWER" | grep -qiE "rm -rf /d" && block "D: drive recursive delete" "Only delete in your safe zone ($SAFE_ZONE)"
      ;;
    macos)
      echo "$CMD_LOWER" | grep -qiE "rm -rf /(system|library|applications)" && block "macOS system recursive delete" "Only delete in your safe zone ($SAFE_ZONE)"
      ;;
    linux)
      echo "$CMD_LOWER" | grep -qiE "rm -rf /(usr|etc|var|boot|lib)" && block "System directory recursive delete" "Only delete in your safe zone ($SAFE_ZONE)"
      ;;
  esac
fi

# Windows-specific recursive delete commands
if [ "$OS_TYPE" = "windows" ] || [ "$OS_TYPE" = "wsl" ]; then
  echo "$CMD_LOWER" | grep -qiE "del /s /q c:" && block "Recursive delete on C:" "Only use del /s on safe zone directories"
  echo "$CMD_LOWER" | grep -qiE "rmdir /s /q c:" && block "Recursive rmdir on C:" "Only use rmdir /s on safe zone directories"
fi

# ══════════════════════════════════════════════════════════════════
# RULE 5: SYSTEM PATHS (write/delete protection)
# ══════════════════════════════════════════════════════════════════

if targets_system; then
  echo "$CMD_LOWER" | grep -qiE "(rm|del|rmdir|mv|move|>)" && block "Modifying system directory" "Work in your safe zone ($SAFE_ZONE) instead. System files should not be modified by automation."
fi

if [ "$OS_TYPE" = "windows" ] || [ "$OS_TYPE" = "wsl" ]; then
  echo "$CMD_LOWER" | grep -qiE "(rm|del|rmdir|mv|move).*/c/users/[^/]+/(ntuser)" && block "Modifying Windows user registry hive" "This file controls your user profile. Do not modify it."
fi

# ══════════════════════════════════════════════════════════════════
# RULE 6: REGISTRY & SERVICES (OS-gated)
# ══════════════════════════════════════════════════════════════════

case "$OS_TYPE" in
  windows|wsl)
    echo "$CMD_LOWER" | grep -qiE "reg (delete|add|import)" && block "Registry modification" "Use the Settings app or regedit GUI for registry changes"
    echo "$CMD_LOWER" | grep -qiE "sc (delete|stop|config|create)" && block "Windows service modification" "Use Services MMC (services.msc) or Task Manager instead"
    echo "$CMD_LOWER" | grep -qiE "schtasks.*/create" && block "Scheduled task creation" "Use Task Scheduler GUI instead"
    echo "$CMD_LOWER" | grep -qiE "netsh.*(firewall|advfirewall)" && block "Firewall modification" "Use Windows Security > Firewall settings instead"
    echo "$CMD_LOWER" | grep -qiE "net (user|localgroup)" && block "User/group modification" "Use Settings > Accounts instead"
    ;;
  macos)
    echo "$CMD_LOWER" | grep -qiE "launchctl.*(load|unload|bootout)" && block "Launch daemon modification" "Use System Preferences instead"
    echo "$CMD_LOWER" | grep -qiE "defaults write.*/library/preferences" && block "System preferences modification" "Use System Preferences GUI instead"
    echo "$CMD_LOWER" | grep -qiE "dscl.*/users" && block "User modification" "Use System Preferences > Users instead"
    ;;
  linux)
    echo "$CMD_LOWER" | grep -qiE "systemctl.*(disable|mask|stop).*\b(ssh|sshd|ufw|iptables|docker)\b" && block "Critical service modification" "Use your system's service manager GUI instead"
    echo "$CMD_LOWER" | grep -qiE "useradd|userdel|usermod" && block "User modification" "Use your system's user management GUI instead"
    echo "$CMD_LOWER" | grep -qiE "iptables.*-(A|D|F|X)" && block "Firewall modification" "Use ufw or your distro's firewall GUI instead"
    ;;
esac

# ══════════════════════════════════════════════════════════════════
# RULE 7: CREDENTIAL ACCESS
# ══════════════════════════════════════════════════════════════════
# Block: sending creds over network (exfiltration)
# Allow: reading .env locally for development (contained)

if echo "$CMD_LOWER" | grep -qiE "(curl|wget).*(\.env|password|credential|ssh.*key|secret)"; then
  block "Sending sensitive data over network" \
    "Read the credential file locally instead. Never include secrets in curl/wget commands."
fi
if echo "$CMD_LOWER" | grep -qiE "cat.*(\.ssh/id_|\.gnupg/|\.aws/credentials)"; then
  block "Reading sensitive credential files via cat" \
    "Use 'ls -la' to check the file exists, or 'ssh-add -l' to verify loaded keys, instead of displaying the key content"
fi

# ══════════════════════════════════════════════════════════════════
# RULE 8: RESOURCE EXHAUSTION
# ══════════════════════════════════════════════════════════════════

echo "$CMD_LOWER" | grep -qiE ":\\(\\).*\\{.*:\\|:" && block "Fork bomb" "This is never needed. Use proper process management."
echo "$CMD_LOWER" | grep -qiE "yes \|" && block "Infinite output pipe" "Use 'echo y |' for a single confirmation instead of 'yes |'"

# ══════════════════════════════════════════════════════════════════
# RULE 9: PERMISSIONS (relax for safe zone)
# ══════════════════════════════════════════════════════════════════

if echo "$CMD_LOWER" | grep -qiE "chmod.*777"; then
  if targets_safe_zone; then
    log_contained "chmod 777 in safe zone — allowed (contained)"
    log_ok
    exit 0
  fi
  block "chmod 777 outside dev zone" "Use chmod 755 for executables or chmod 644 for files. Or work in your safe zone ($SAFE_ZONE)."
fi
echo "$CMD_LOWER" | grep -qiE "icacls.*/grant.*everyone" && block "Granting Everyone access" "Grant access to specific users instead"

# ══════════════════════════════════════════════════════════════════
# PASSED ALL CHECKS
# ══════════════════════════════════════════════════════════════════

LOG_FILE="$LOG_DIR/commands.log"
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] OK | $COMMAND" >> "$LOG_FILE"

# Rotate at 10MB (cross-platform stat)
if [ -f "$LOG_FILE" ]; then
  FILE_SIZE=0
  case "$OS_TYPE" in
    macos) FILE_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0) ;;
    *)     FILE_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) ;;
  esac
  if [ "$FILE_SIZE" -gt 10485760 ] 2>/dev/null; then
    mv "$LOG_FILE" "$LOG_FILE.old"
  fi
fi

exit 0
